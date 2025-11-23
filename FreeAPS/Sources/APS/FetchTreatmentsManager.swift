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
    @Injected() var broadcaster: Broadcaster!
    @Injected() var settingsManager: SettingsManager!

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
    private let shouldFetch = PassthroughSubject<Bool, Never>()

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
                let filteredCarbs = carbs.filter { !($0.enteredBy?.contains(CarbsEntry.manual) ?? false) }
                if filteredCarbs.isNotEmpty {
                    self.carbsStorage.storeCarbs(filteredCarbs)
                }
                let filteredTargets = targets.filter { !($0.enteredBy?.contains(TempTarget.manual) ?? false) }
                if filteredTargets.isNotEmpty {
                    self.tempTargetsStorage.storeTempTargets(filteredTargets)
                }
            }
            .store(in: &lifetime)

        shouldFetch
            .removeDuplicates()
            .receive(on: processQueue)
            .sink { shouldFetch in
                if shouldFetch {
                    self.timer.fire()
                    self.timer.resume()
                } else {
                    self.timer.suspend()
                }
            }
            .store(in: &lifetime)

        broadcaster.register(SettingsObserver.self, observer: self)
        settingsDidChange(settingsManager.settings)
    }
}

extension BaseFetchTreatmentsManager: SettingsObserver {
    func settingsDidChange(_ settings: FreeAPSSettings) {
        shouldFetch.send(settings.nightscoutFetchEnabled)
    }
}
