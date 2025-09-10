import Combine
import Foundation
import G7SensorKit
import LoopKit
import LoopKitUI
import Swinject

// TODO: better name?
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

        subscribe()
    }

    private func subscribe() {
        appCoordinator.bloodGlucose
            .flatMap { bloodGlucose in
                self.healthKitManager.fetch().map { glucoseFromHealth in (bloodGlucose, glucoseFromHealth) }.eraseToAnyPublisher()
            }
            .receive(on: processQueue)
            .sink { bloodGlucose, glucoseFromHealth in
                let syncDate = self.glucoseStorage.syncDate()

                self.glucoseStoreAndHeartDecision(
                    syncDate: syncDate,
                    glucose: bloodGlucose,
                    glucoseFromHealth: glucoseFromHealth
                )
            }
            .store(in: &lifetime)
    }

    private func glucoseStoreAndHeartDecision(
        syncDate: Date,
        glucose: [BloodGlucose],
        glucoseFromHealth: [BloodGlucose]
    ) {
        let allGlucose = glucose + glucoseFromHealth
        var filteredByDate: [BloodGlucose] = []
        var filtered: [BloodGlucose] = []

        // start background time extension
        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
            guard let bg = backGroundFetchBGTaskID else { return }
            UIApplication.shared.endBackgroundTask(bg)
            backGroundFetchBGTaskID = .invalid
        }

        guard allGlucose.isNotEmpty else {
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return
        }

        filteredByDate = allGlucose.filter { $0.dateString > syncDate }
        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        guard filtered.isNotEmpty else {
            // end of the BG tasks
            if let backgroundTask = backGroundFetchBGTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundFetchBGTaskID = .invalid
            }
            return
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

        appCoordinator.sendHeartbeat(date: Date())

        nightscoutManager.uploadGlucose()

        // end of the BG tasks
        if let backgroundTask = backGroundFetchBGTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundFetchBGTaskID = .invalid
        }

        let glucoseForHealth = filteredByDate.filter { !glucoseFromHealth.contains($0) }
        guard glucoseForHealth.isNotEmpty else {
            return
        }
        healthKitManager.saveIfNeeded(bloodGlucose: glucoseForHealth)
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
