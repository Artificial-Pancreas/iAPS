import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchTreatmentsManager {}

actor BaseFetchTreatmentsManager: FetchTreatmentsManager, Injectable {
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var carbsStorage: CarbsStorage!
    @Injected() var appCoordinator: AppCoordinator!
    @Injected() var settingsManager: SettingsManager!

    private let coreDataStorage = CoreDataStorage()

    private var lifetime = Lifetime()

    private let interval: TimeInterval = .minutes(1)
    private var pollingTask: Task<Void, Never>?
    private var fetchEnabled = false

    init(resolver: Resolver) {
        injectServices(resolver)
        Task {
            await subscribe()
        }
    }

    private func subscribe() async {
        let settings = await settingsManager.settings
        settingsUpdated(settings)

        observe(appCoordinator.settingsUpdates, in: &lifetime) { settings in
            await self.settingsUpdated(settings)
        }
    }

    func settingsUpdated(_ settings: FreeAPSSettings) {
        let enabled = settings.nightscoutFetchEnabled
        guard enabled != fetchEnabled else { return }
        fetchEnabled = enabled
        enabled ? startPolling() : stopPolling()
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let interval = self?.interval else { return }
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func poll() async {
        debug(.nightscout, "FetchTreatmentsManager heartbeat")
        debug(.nightscout, "Start fetching carbs and temptargets")
        async let carbs = nightscoutManager.fetchCarbs()
        async let targets = nightscoutManager.fetchTempTargets()

        let filteredCarbs = await carbs.filter { !($0.enteredBy?.contains(CarbsEntry.manual) ?? false) }
        if filteredCarbs.isNotEmpty {
            coreDataStorage.saveMeals(filteredCarbs)
            await self.carbsStorage.storeCarbs(filteredCarbs)
        }
        let filteredTargets = await targets.filter { !($0.enteredBy?.contains(TempTarget.manual) ?? false) }
        if filteredTargets.isNotEmpty {
            await self.tempTargetsStorage.storeTempTargets(filteredTargets)
        }
    }
}
