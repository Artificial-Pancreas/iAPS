import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchGlucoseManager: SourceInfoProvider {}

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

    private lazy var dexcomSource = DexcomSource()
    private lazy var simulatorSource = GlucoseSimulatorSource()

    init(resolver: Resolver) {
        injectServices(resolver)
        updateGlucoseSource()
        subscribe()
    }

    var glucoseSource: GlucoseSource!

    private func updateGlucoseSource() {
        switch settingsManager.settings.cgm {
        case .xdrip:
            glucoseSource = AppGroupSource(from: "xDrip")
        case .dexcomG5,
             .dexcomG6:
            glucoseSource = dexcomSource
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
        }
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { date -> AnyPublisher<(Date, Date, [BloodGlucose], [BloodGlucose]), Never> in
                debug(.nightscout, "FetchGlucoseManager heartbeat")
                debug(.nightscout, "Start fetching glucose")
                self.updateGlucoseSource()
                return Publishers.CombineLatest4(
                    Just(date),
                    Just(self.glucoseStorage.syncDate()),
                    self.glucoseSource.fetch(),
                    self.healthKitManager.fetch()
                )
                .eraseToAnyPublisher()
            }
            .sink { date, syncDate, glucose, glucoseFromHealth in
                debug(.nightscout, "SyncDate is \(syncDate)")
                let allGlucose = glucose + glucoseFromHealth
                guard allGlucose.isNotEmpty else { return }

                // Because of Spike dosn't respect a date query
                let filteredByDate = allGlucose.filter { $0.dateString > syncDate }
                let filtered = self.glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

                guard filtered.isNotEmpty else { return }
                debug(.nightscout, "New glucose found")

                self.glucoseStorage.storeGlucose(filtered)
                self.apsManager.heartbeat(date: date)
                self.nightscoutManager.uploadGlucose()
                let glucoseForHealth = filteredByDate.filter { !glucoseFromHealth.contains($0) }

                guard glucoseForHealth.isNotEmpty else { return }
                self.healthKitManager.saveIfNeeded(bloodGlucose: glucoseForHealth)
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()

        UserDefaults.standard
            .publisher(for: \.dexcomTransmitterID)
            .removeDuplicates()
            .sink { id in
                guard [.dexcomG5, .dexcomG6].contains(self.settingsManager.settings.cgm) else { return }
                if id != self.dexcomSource.transmitterID {
                    self.dexcomSource = DexcomSource()
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
