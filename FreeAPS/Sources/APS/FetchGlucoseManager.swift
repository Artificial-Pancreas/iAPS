import Combine
import Foundation
import SwiftDate
import Swinject
import UIKit

// protocol FetchGlucoseManager: SourceInfoProvider {
//    func updateGlucoseStore(newBloodGlucose: [BloodGlucose]) async
//    func refreshCGM() async
//    func updateGlucoseSource()
//    var cgmGlucoseSourceType: CGMType? { get set }
// }
//
// final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
//    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
//    private let glucoseStorage: GlucoseStorage
//    private let nightscoutManager: NightscoutManager!
//    private let apsManager: APSManager
//    private let settingsManager: SettingsManager
//    private let healthKitManager: HealthKitManager
//    private let deviceDataManager: DeviceDataManager
//    private let calibrationService: CalibrationService
//
//    private let coredataContext = CoreDataStack.shared.persistentContainer.viewContext
//    private var lifetime = Lifetime()
//    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
//    var cgmGlucoseSourceType: CGMType?
//
//    private let cgmPluginManager: CGMPluginManager
//
//    init(resolver: Resolver) {
//        glucoseStorage = resolver.resolve(GlucoseStorage.self)!
//        nightscoutManager = resolver.resolve(NightscoutManager.self)!
//        apsManager = resolver.resolve(APSManager.self)!
//        settingsManager = resolver.resolve(SettingsManager.self)!
//        healthKitManager = resolver.resolve(HealthKitManager.self)!
//        deviceDataManager = resolver.resolve(DeviceDataManager.self)!
//        calibrationService = resolver.resolve(CalibrationService.self)!
//        cgmPluginManager = resolver.resolve(CGMPluginManager.self)!
//
//        // TODO: [loopkit] fix this
////        dexcomSourceG5 = DexcomSourceG5(glucoseStorage: glucoseStorage, glucoseManager: self)
////        dexcomSourceG6 = DexcomSourceG6(glucoseStorage: glucoseStorage, glucoseManager: self)
////        dexcomSourceG7 = DexcomSourceG7(glucoseStorage: glucoseStorage, glucoseManager: self)
////        simulatorSource = GlucoseSimulatorSource()
//
////        libreTransmitter = BaseLibreTransmitterSource(
////            glucoseStorage: glucoseStorage,
////            glucoseManager: self,
////            calibrationService: calibrationService
////        )
//
//        updateGlucoseSource()
//        subscribe()
//    }
//
//    func updateGlucoseSource() {
//        // Use CGM manager from DeviceDataManager
//        if let cgmManager = deviceDataManager.cgmManager {
//            cgmPluginManager.setCGMManager(cgmManager)
////            glucoseSource = cgmPluginManager
//        } else {
//            // Fallback to nightscout
////            glucoseSource = nightscoutManager
//        }
//
//        // Update legacy property for backward compatibility
//        cgmGlucoseSourceType = settingsManager.settings.cgm
//    }
//
////    var glucoseSource: GlucoseSource!
//
//    /// function called when a callback is fired by CGM BLE - no more used
//    @MainActor public func updateGlucoseStore(newBloodGlucose: [BloodGlucose]) {
//        let syncDate = glucoseStorage.syncDate()
//        debug(.deviceManager, "CGM BLE FETCHGLUCOSE  : SyncDate is \(syncDate)")
//        glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: newBloodGlucose)
//    }
//
//    /// function to try to force the refresh of the CGM - generally provide by the pump heartbeat
//    @MainActor public func refreshCGM() {
//        debug(.deviceManager, "refreshCGM by pump")
//        updateGlucoseSource()
//        Publishers.CombineLatest3(
//            Just(glucoseStorage.syncDate()),
//            healthKitManager.fetch(nil),
//            cgmPluginManager.fetchIfNeeded()
////            glucoseSource.fetchIfNeeded()
//        )
//        .eraseToAnyPublisher()
//        .receive(on: processQueue)
//        .sink { syncDate, glucoseFromHealth, glucose in
//            debug(.nightscout, "refreshCGM FETCHGLUCOSE : SyncDate is \(syncDate)")
//            self.glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: glucose, glucoseFromHealth: glucoseFromHealth)
//        }
//        .store(in: &lifetime)
//    }
//
//    private func glucoseStoreAndHeartDecision(
//        syncDate: Date,
//        glucose: [BloodGlucose] = [],
//        glucoseFromHealth: [BloodGlucose] = []
//    ) {
//        let allGlucose = glucose + glucoseFromHealth
//        var filteredByDate: [BloodGlucose] = []
//        var filtered: [BloodGlucose] = []
//
//        // start background time extension
//        var backGroundFetchBGTaskID: UIBackgroundTaskIdentifier?
//        backGroundFetchBGTaskID = UIApplication.shared.beginBackgroundTask(withName: "save BG starting") {
//            guard let bg = backGroundFetchBGTaskID else { return }
//            UIApplication.shared.endBackgroundTask(bg)
//            backGroundFetchBGTaskID = .invalid
//        }
//
//        guard allGlucose.isNotEmpty else {
//            if let backgroundTask = backGroundFetchBGTaskID {
//                UIApplication.shared.endBackgroundTask(backgroundTask)
//                backGroundFetchBGTaskID = .invalid
//            }
//            return
//        }
//
//        filteredByDate = allGlucose.filter { $0.dateString > syncDate }
//        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)
//
//        guard filtered.isNotEmpty else {
//            // end of the BG tasks
//            if let backgroundTask = backGroundFetchBGTaskID {
//                UIApplication.shared.endBackgroundTask(backgroundTask)
//                backGroundFetchBGTaskID = .invalid
//            }
//            return
//        }
//        debug(.deviceManager, "New glucose found")
//
//        // filter the data if it is the case
//        if settingsManager.settings.smoothGlucose {
//            // limit to 30 minutes of previous BG Data
//            let oldGlucoses = glucoseStorage.recent().filter {
//                $0.dateString.addingTimeInterval(31 * 60) > Date()
//            }
//            var smoothedValues = oldGlucoses + filtered
//            // smooth with 3 repeats
//            for _ in 1 ... 3 {
//                smoothedValues.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
//            }
//            // find the new values only
//            filtered = smoothedValues.filter { $0.dateString > syncDate }
//        }
//
//        save(filtered)
//
//        glucoseStorage.storeGlucose(filtered)
//
//        deviceDataManager.heartbeat(date: Date())
//
//        nightscoutManager.uploadGlucose()
//
//        // end of the BG tasks
//        if let backgroundTask = backGroundFetchBGTaskID {
//            UIApplication.shared.endBackgroundTask(backgroundTask)
//            backGroundFetchBGTaskID = .invalid
//        }
//
//        let glucoseForHealth = filteredByDate.filter { !glucoseFromHealth.contains($0) }
//        guard glucoseForHealth.isNotEmpty else {
//            return
//        }
//        healthKitManager.saveIfNeeded(bloodGlucose: glucoseForHealth)
//    }
//
//    /// The function used to start the timer sync - Function of the variable defined in config
//    private func subscribe() {
//        timer.publisher
//            .receive(on: processQueue)
//            .flatMap { _ -> AnyPublisher<[BloodGlucose], Never> in
//                debug(.nightscout, "FetchGlucoseManager timer heartbeat")
//                self.updateGlucoseSource()
//                return self.cgmPluginManager.fetch(self.timer).eraseToAnyPublisher()
//            }
//            .receive(on: processQueue)
//            .flatMap { glucose in
//                debug(.nightscout, "FetchGlucoseManager callback sensor")
//                return Publishers.CombineLatest3(
//                    Just(glucose),
//                    Just(self.glucoseStorage.syncDate()),
//                    self.healthKitManager.fetch(nil)
//                )
//                .eraseToAnyPublisher()
//            }
//            .receive(on: processQueue)
//            .sink { newGlucose, syncDate, glucoseFromHealth in
//                self.glucoseStoreAndHeartDecision(
//                    syncDate: syncDate,
//                    glucose: newGlucose,
//                    glucoseFromHealth: glucoseFromHealth
//                )
//            }
//            .store(in: &lifetime)
//
//        timer.fire()
//        timer.resume()
//
//        UserDefaults.standard
//            .publisher(for: \.dexcomTransmitterID)
//            .removeDuplicates()
//            .sink { _ in
//                // TODO: [loopkit] fix this
////                if self.settingsManager.settings.cgm == .dexcomG5 {
////                    if id != self.dexcomSourceG5.transmitterID {
//                ////                        self.dexcomSourceG5 = DexcomSourceG5(glucoseStorage: self.glucoseStorage, glucoseManager: self) // TODO: fix this
////                    }
////                } else if self.settingsManager.settings.cgm == .dexcomG6 {
////                    if id != self.dexcomSourceG6.transmitterID {
//                ////                        self.dexcomSourceG6 = DexcomSourceG6(glucoseStorage: self.glucoseStorage, glucoseManager: self) // TODO: fix this
////                    }
////                }
//            }
//            .store(in: &lifetime)
//    }
//
//    private func save(_ glucose: [BloodGlucose]) {
//        guard glucose.isNotEmpty, let first = glucose.first, let glucose = first.glucose, glucose != 0 else { return }
//
//        coredataContext.perform {
//            let dataForForStats = Readings(context: self.coredataContext)
//            dataForForStats.date = first.dateString
//            dataForForStats.glucose = Int16(glucose)
//            dataForForStats.id = first.id
//            dataForForStats.direction = first.direction?.symbol ?? "↔︎"
//            try? self.coredataContext.save()
//        }
//    }
//
//    func sourceInfo() -> [String: Any]? {
//        self.cgmPluginManager.sourceInfo()
//    }
// }

// extension UserDefaults {
//    @objc var dexcomTransmitterID: String? {
//        get {
//            string(forKey: "DexcomSource.transmitterID")?.nonEmpty
//        }
//        set {
//            set(newValue, forKey: "DexcomSource.transmitterID")
//        }
//    }
// }
