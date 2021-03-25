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
    private let timer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        timer
            .receive(on: processQueue)
            .flatMap { date -> AnyPublisher<[BloodGlucose], Never> in
                guard self.glucoseStogare.syncDate().timeIntervalSince1970 + 4.minutes.timeInterval <= date.timeIntervalSince1970
                else {
                    return Just([]).eraseToAnyPublisher()
                }
                return self.nightscoutManager.fetchGlucose()
            }
            .sink { glucose in
                if !glucose.isEmpty {
                    self.apsManager.heartbeatNow()
                }
            }
            .store(in: &lifetime)
    }
}
