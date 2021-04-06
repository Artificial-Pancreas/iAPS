import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchTreatmentsManager {}

final class BaseFetchTreatmentsManager: FetchTreatmentsManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseFetchTreatmentsManager.processQueue")
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var carbsStorage: CarbsStorage!

    private var lifetime = Set<AnyCancellable>()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { _ -> AnyPublisher<([CarbsEntry], [TempTarget]), Never> in
                debug(.nightscout, "FetchTreatmentsManager heartbeat")
                debug(.nightscout, "Start fetching carbs and temptargets")
                return Publishers.CombineLatest(
                    self.nightscoutManager.fetchCarbs(),
                    self.nightscoutManager.fetchTempTargets()
                ).eraseToAnyPublisher()
            }
            .sink { carbs, targets in
                if carbs.isNotEmpty {
                    self.carbsStorage.storeCarbs(carbs)
                }
                if targets.isNotEmpty {
                    self.tempTargetsStorage.storeTempTargets(targets)
                }
            }
            .store(in: &lifetime)
        timer.resume()
    }
}
