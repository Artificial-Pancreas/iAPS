import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchGlucoseManager: SourceInfoProvider {
    func updateGlucoseStore(newBloodGlucose: [BloodGlucose])
    func refreshCGM()
}

final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var libreTransmitter: LibreTransmitterSource!
    @Injected() var healthKitManager: HealthKitManager!
    @Injected() var deviceDataManager: DeviceDataManager!

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    private lazy var dexcomSourceG5 = DexcomSourceG5(glucoseStorage: glucoseStorage, glucoseManager: self)
    private lazy var dexcomSourceG6 = DexcomSourceG6(glucoseStorage: glucoseStorage, glucoseManager: self)
    private lazy var dexcomSourceG7 = DexcomSourceG7(glucoseStorage: glucoseStorage, glucoseManager: self)
    private lazy var simulatorSource = GlucoseSimulatorSource()

    init(resolver: Resolver) {
        injectServices(resolver)
        updateGlucoseSource()
        subscribe()

        /// listen if require CGM update
        deviceDataManager.requireCGMRefresh
            .receive(on: processQueue)
            .sink { _ in
                self.refreshCGM()
            }
            .store(in: &lifetime)
    }

    var glucoseSource: GlucoseSource!

    private func updateGlucoseSource() {
        switch settingsManager.settings.cgm {
        case .xdrip:
            glucoseSource = AppGroupSource(from: "xDrip")
        case .dexcomG5:
            glucoseSource = dexcomSourceG5
        case .dexcomG6:
            glucoseSource = dexcomSourceG6
        case .dexcomG7:
            glucoseSource = dexcomSourceG7
        case .nightscout:
            glucoseSource = nightscoutManager
        case .simulator:
            glucoseSource = simulatorSource
        case .libreTransmitter:
            glucoseSource = libreTransmitter
        case .glucoseDirect:
            glucoseSource = AppGroupSource(from: "GlucoseDirect")
        case .enlite:
            glucoseSource = deviceDataManager
        }

        if settingsManager.settings.cgm != .libreTransmitter {
            libreTransmitter.manager = nil
        } else {
            libreTransmitter.glucoseManager = self
        }
    }

    /// function called when a callback is fired by CGM BLE
    public func updateGlucoseStore(newBloodGlucose: [BloodGlucose]) {
        let syncDate = glucoseStorage.syncDate()
        debug(.deviceManager, "CGM BLE FETCHGLUCOSE  : SyncDate is \(syncDate)")
        glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: newBloodGlucose)
    }

    /// function to try to force the refresh of the CGM - generally provide by the pump heartbeat
    public func refreshCGM() {
        debug(.deviceManager, "refreshCGM by pump")
        updateGlucoseSource()
        Publishers.CombineLatest3(
            Just(glucoseStorage.syncDate()),
            healthKitManager.fetch(nil),
            glucoseSource.fetchIfNeeded()
        )
        .eraseToAnyPublisher()
        .receive(on: processQueue)
        .sink { syncDate, glucoseFromHealth, glucose in
            debug(.nightscout, "refreshCGM FETCHGLUCOSE : SyncDate is \(syncDate)")
            self.glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: glucose, glucoseFromHealth: glucoseFromHealth)
        }
        .store(in: &lifetime)
    }

    private func glucoseStoreAndHeartDecision(syncDate: Date, glucose: [BloodGlucose], glucoseFromHealth: [BloodGlucose] = []) {
        let allGlucose = glucose + glucoseFromHealth
        var filteredByDate: [BloodGlucose] = []
        var filtered: [BloodGlucose] = []

        if allGlucose.isNotEmpty {
            filteredByDate = allGlucose.filter { $0.dateString > syncDate }
            filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)
            if filtered.isNotEmpty {
                debug(.nightscout, "New glucose found")
                glucoseStorage.storeGlucose(filtered)
            }
        }

        if filtered.isEmpty {
            let lastGlucoseDate = glucoseStorage.lastGlucoseDate()
            guard lastGlucoseDate >= Date().addingTimeInterval(Config.eхpirationInterval) else {
                debug(.nightscout, "Glucose is too old - \(lastGlucoseDate)")
                return
            }
        }

        apsManager.heartbeat(date: Date())

        // no need to go next step if no new data
        guard filteredByDate.isNotEmpty else {
            return
        }

        nightscoutManager.uploadGlucose()
        let glucoseForHealth = filteredByDate.filter { !glucoseFromHealth.contains($0) }
        guard glucoseForHealth.isNotEmpty else { return }
        healthKitManager.saveIfNeeded(bloodGlucose: glucoseForHealth)
    }

    /// The function used to start the timer sync - Function of the variable defined in config
    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { date -> AnyPublisher<(Date, Date, [BloodGlucose], [BloodGlucose]), Never> in
                debug(.nightscout, "FetchGlucoseManager heartbeat")
                self.updateGlucoseSource()
                return Publishers.CombineLatest4(
                    Just(date),
                    Just(self.glucoseStorage.syncDate()),
                    self.glucoseSource.fetch(self.timer),
                    self.healthKitManager.fetch(nil)
                )
                .eraseToAnyPublisher()
            }
            .sink { _, syncDate, glucose, glucoseFromHealth in
                debug(.nightscout, "FETCHGLUCOSE : SyncDate is \(syncDate)")
                self.glucoseStoreAndHeartDecision(syncDate: syncDate, glucose: glucose, glucoseFromHealth: glucoseFromHealth)
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()

        UserDefaults.standard
            .publisher(for: \.dexcomTransmitterID)
            .removeDuplicates()
            .sink { id in
                if self.settingsManager.settings.cgm == .dexcomG5 {
                    if id != self.dexcomSourceG5.transmitterID {
                        self.dexcomSourceG5 = DexcomSourceG5(glucoseStorage: self.glucoseStorage, glucoseManager: self)
                    }
                } else if self.settingsManager.settings.cgm == .dexcomG6 {
                    if id != self.dexcomSourceG6.transmitterID {
                        self.dexcomSourceG6 = DexcomSourceG6(glucoseStorage: self.glucoseStorage, glucoseManager: self)
                    }
                }
            }
            .store(in: &lifetime)
    }

    func sourceInfo() -> [String: Any]? {
        glucoseSource.sourceInfo()
    }
}

extension UserDefaults {
    @objc var dexcomTransmitterID: String? {
        get {
            string(forKey: "DexcomSource.transmitterID")?.nonEmpty
        }
        set {
            set(newValue, forKey: "DexcomSource.transmitterID")
        }
    }
}
