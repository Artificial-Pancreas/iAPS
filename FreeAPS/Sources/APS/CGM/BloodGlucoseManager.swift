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
    private let healthKitManager: HealthKitManager
    private let appCoordinator: AppCoordinator

    private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    private var lifetime = Lifetime()

    init(resolver: Resolver) {
        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        nightscoutManager = resolver.resolve(NightscoutManager.self)!
        healthKitManager = resolver.resolve(HealthKitManager.self)!
        appCoordinator = resolver.resolve(AppCoordinator.self)!
    }

    /// return true if new blood glucose record was detected and stored
    func storeNewBloodGlucose(
        bloodGlucose: [BloodGlucose],
        completion: @escaping (Bool) -> Void
    ) {
        processQueue.async {
            let glucoseFromHealth = self.healthKitManager.fetch()
            let syncDate = self.glucoseStorage.syncDate()

            let newBloodGlucoseStored = self.glucoseStoreAndHeartDecision(
                syncDate: syncDate,
                glucose: bloodGlucose,
                glucoseFromHealth: glucoseFromHealth
            )
            completion(newBloodGlucoseStored)
        }
    }

    private func glucoseStoreAndHeartDecision(
        syncDate: Date,
        glucose: [BloodGlucose],
        glucoseFromHealth: [BloodGlucose]
    ) -> Bool {
        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            UIApplication.shared.endBackgroundTask(bg)
            backGroundFetchBGTaskID = .invalid
        }

        let allGlucose = glucose + glucoseFromHealth

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
//        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        guard filtered.isNotEmpty else {
            // end of the BG tasks
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return false
        }
        debug(.deviceManager, "New glucose found")

        // filter the data if it is the case
        if settingsManager.settings.smoothGlucose {
            // limit to 30 minutes of previous BG Data
            let oldGlucoses = glucoseStorage.recent().filter {
                $0.dateString.addingTimeInterval(31 * 60) > Date()
            }
            var smoothedValues = oldGlucoses + filtered
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                smoothedValues.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
            // find the new values only
            filtered = smoothedValues.filter { $0.dateString > syncDate }
        }

        save(filtered)

        glucoseStorage.storeGlucose(filtered)

        // TODO: [loopkit] the code below used to be executed in parallel with the rest of the loop
        nightscoutManager.uploadGlucose()

        let glucoseForHealth = allGlucose.filter { !glucoseFromHealth.contains($0) }
        if glucoseForHealth.isNotEmpty {
            healthKitManager.saveIfNeeded(bloodGlucose: glucoseForHealth)
        }

        let updatedGlucose = glucoseStorage.recent()

        // if a newer blood glucose record was stored - we will return `true`
        // this will tell the DeviceDataMager to trigger a loop recommendation
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
