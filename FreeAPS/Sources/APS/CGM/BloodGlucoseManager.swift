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
            let syncDate = self.glucoseStorage.syncDate()

            let newBloodGlucoseStored = self.glucoseStoreAndHeartDecision(
                syncDate: syncDate,
                glucose: bloodGlucose
            )
            completion(newBloodGlucoseStored)
        }
    }

    private func glucoseStoreAndHeartDecision(
        syncDate: Date,
        glucose: [BloodGlucose]
    ) -> Bool {
        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            UIApplication.shared.endBackgroundTask(bg)
            backGroundFetchBGTaskID = .invalid
        }

        let allGlucose = glucose

        guard allGlucose.isNotEmpty else {
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return false
        }

        var filtered: [BloodGlucose] = []

        let recentGlucose = glucoseStorage.recent()

        filtered = allGlucose

        guard filtered.isNotEmpty else {
            // end of the BG tasks
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return false
        }
        debug(.deviceManager, "New glucose found")

        // TODO: [loopkit] revisit this (we now have backfill)
        if settingsManager.settings.smoothGlucose {
            // limit to 30 minutes of previous BG Data
            let now = Date()
            let oldGlucoses = recentGlucose.filter {
                $0.dateString.addingTimeInterval(31 * 60) > now
            }
            var smoothedValues = oldGlucoses + filtered
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                smoothedValues.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
            // find the new values only
            // TODO: [loopkit] fix this filter
            filtered = smoothedValues.filter { $0.dateString > syncDate }
        }

        save(filtered)

        glucoseStorage.storeGlucose(filtered)

        // TODO: do not commit this!
        glucoseStorage.storeGlucose(filtered)

        // TODO: [loopkit] move this out of the main loop, upload in the background
        nightscoutManager.uploadGlucose()

        let updatedGlucose = glucoseStorage.recent()

        // recommend a loop only if a newer blood glucose record was stored
        let previousLatestBG = recentGlucose.map(\.dateString).max()
        let updatedLatestBG = updatedGlucose.map(\.dateString).max()

        var newGlucoseStored = false
        if let previousLatestBG, let updatedLatestBG {
            newGlucoseStored = updatedLatestBG > previousLatestBG
        } else {
            newGlucoseStored = previousLatestBG == nil && updatedLatestBG != nil
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
