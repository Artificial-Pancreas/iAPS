import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchGlucoseManager {}

final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!
    @Injected() var settingsManager: SettingsManager!

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    private lazy var appGroupSource = AppGroupSource()
    private lazy var dexcomSource = DexcomSource()

    init(resolver: Resolver) {
        injectServices(resolver)
        updateGlucoseSource()
        subscribe()
    }

    var glucoseSource: GlucoseSource!

    private func updateGlucoseSource() {
        switch settingsManager.settings.cgm {
        case .xdrip:
            glucoseSource = appGroupSource
        case .dexcomG5,
             .dexcomG6:
            glucoseSource = dexcomSource
        case .nightscout,
             .none:
            glucoseSource = nightscoutManager
        }
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { date -> AnyPublisher<(Date, Date, [BloodGlucose]), Never> in
                debug(.nightscout, "FetchGlucoseManager heartbeat")
                debug(.nightscout, "Start fetching glucose")
                self.updateGlucoseSource()
                return Publishers.CombineLatest3(
                    Just(date),
                    Just(self.glucoseStorage.syncDate()),
                    self.glucoseSource.fetch()
                )
                .eraseToAnyPublisher()
            }
            .sink { date, syncDate, glucose in
                // Because of Spike dosn't respect a date query
                let filteredByDate = glucose.filter { $0.dateString > syncDate }
                let filtered = self.glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)
                if !filtered.isEmpty {
                    debug(.nightscout, "New glucose found")
                    self.glucoseStorage.storeGlucose(filtered)
                    self.apsManager.heartbeat(date: date, force: false)
                    self.nightscoutManager.uploadGlucose()
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()

        UserDefaults.standard
            .publisher(for: \.dexcomTransmitterID)
            .removeDuplicates()
            .sink { id in
                if id != self.dexcomSource.transmitterID {
                    self.dexcomSource = DexcomSource()
                }
            }
            .store(in: &lifetime)
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
