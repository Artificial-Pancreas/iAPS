import Combine
import Foundation
import G7SensorKit
import LoopKit
import LoopKitUI
import Swinject

final class BloodGlucoseManager {
    private let processQueue = DispatchQueue(label: "BaseCGMPluginManager.processQueue")
    private let glucoseStorage: GlucoseStorage
    private let settingsManager: SettingsManager
    private let nightscoutManager: NightscoutManager

    private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    private var lifetime = Lifetime()

    init(resolver: Resolver) {
        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        nightscoutManager = resolver.resolve(NightscoutManager.self)!
    }

    /// return true if a newer blood glucose record was detected and stored
    func storeNewBloodGlucose(
        bloodGlucose: [BloodGlucose],
        completion: @escaping (Bool) -> Void
    ) {
        processQueue.async {
            let newBloodGlucoseStored = self.glucoseStoreAndHeartDecision(
                glucose: bloodGlucose
            )
            completion(newBloodGlucoseStored)
        }
    }

    private func glucoseStoreAndHeartDecision(glucose: [BloodGlucose]) -> Bool {
        guard glucose.isNotEmpty else { return false }

        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            UIApplication.shared.endBackgroundTask(bg)
            backGroundFetchBGTaskID = .invalid
        }

        save(glucose)

        let previousLatestBG = glucoseStorage.latestDate()
        glucoseStorage.storeGlucose(glucose)
        let updatedLatestBG = glucoseStorage.latestDate()

        var newGlucoseStored = false
        if let previousLatestBG, let updatedLatestBG {
            newGlucoseStored = updatedLatestBG > previousLatestBG
        } else {
            newGlucoseStored = previousLatestBG == nil && updatedLatestBG != nil
        }

        // TODO: [loopkit] move this out of the main loop, upload in the background
        nightscoutManager.uploadGlucose()

        if newGlucoseStored {
            debug(.deviceManager, "New glucose found")
        }

        // end of the BG tasks
        if let backgroundTask = backGroundFetchBGTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundFetchBGTaskID = .invalid
        }

        return newGlucoseStored
    }

    private func save(_ glucose: [BloodGlucose]) {
        guard glucose.isNotEmpty, let first = glucose.first, let glucose = first.glucose, glucose != 0 else { return }

        coredataContext.perform {
            let dataForForStats = Readings(context: self.coredataContext)
            dataForForStats.date = first.dateString
            dataForForStats.glucose = Int16(glucose)
            dataForForStats.id = first.id
            dataForForStats.direction = first.direction?.symbol ?? "↔︎"
            try? self.coredataContext.save()
        }
    }
}
