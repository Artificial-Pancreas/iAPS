import Combine
import Foundation
import SwiftDate
import Swinject

protocol GlucoseManager {}

final class BaseGlucoseManager: GlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
    @Injected() var glucoseStogare: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!

    private var lifetime = Set<AnyCancellable>()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { _ -> AnyPublisher<(Date, [BloodGlucose]), Never> in
                debug(.nightscout, "Glucose manager heartbeat")
                debug(.nightscout, "Start fetching glucose")
                return Publishers.CombineLatest(Just(self.glucoseStogare.syncDate()), self.nightscoutManager.fetchGlucose())
                    .eraseToAnyPublisher()
            }
            .sink { syncDate, glucose in
                // Because of Spike dosn't respect a date query
                let filteredByDate = glucose.filter { $0.dateString > syncDate }
                let filtered = self.glucoseStogare.filterTooFrequentGlucose(filteredByDate)
                if !filtered.isEmpty {
                    debug(.nightscout, "New glucose found")
                    self.apsManager.heartbeat(force: true)
                } else {
                    self.apsManager.heartbeat(force: false)
                }
            }
            .store(in: &lifetime)
        timer.resume()
    }
}
