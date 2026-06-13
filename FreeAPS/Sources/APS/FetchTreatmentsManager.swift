import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchTreatmentsManager {}

actor BaseFetchTreatmentsManager: FetchTreatmentsManager, LifetimeOwner, AppService {
    private let nightscoutManager: NightscoutManager
    private let tempTargetsStorage: TempTargetsStorage
    private let carbsStorage: CarbsStorage
    private let appCoordinator: AppCoordinator
    private let settingsManager: SettingsManager

    let lifetime = Lifetime()
    private let coreDataStorage = CoreDataStorage()

    private let interval: TimeInterval = .minutes(1)
    private var pollingTask: Task<Void, Never>?
    private var fetchEnabled = false

    init(
        nightscoutManager: NightscoutManager,
        tempTargetsStorage: TempTargetsStorage,
        carbsStorage: CarbsStorage,
        appCoordinator: AppCoordinator,
        settingsManager: SettingsManager,
    ) {
        self.nightscoutManager = nightscoutManager
        self.tempTargetsStorage = tempTargetsStorage
        self.carbsStorage = carbsStorage
        self.appCoordinator = appCoordinator
        self.settingsManager = settingsManager
    }

    // this is called at the start of the app
    func start() async {
        let settings = await settingsManager.settings
        settingsUpdated(settings)

        observe(appCoordinator.settings) { me, settings in
            await me.settingsUpdated(settings)
        }
    }

    func settingsUpdated(_ settings: FreeAPSSettings) {
        let newEnabled = settings.nightscoutFetchEnabled
        guard newEnabled != fetchEnabled else { return }
        fetchEnabled = newEnabled
        if fetchEnabled {
            startPolling()
        } else {
            stopPolling()
        }
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
            await coreDataStorage.saveMeals(filteredCarbs)
            await self.carbsStorage.storeCarbs(filteredCarbs)
        }
        let filteredTargets = await targets.filter { !($0.enteredBy?.contains(TempTarget.manual) ?? false) }
        if filteredTargets.isNotEmpty {
            await self.tempTargetsStorage.storeTempTargets(filteredTargets)
        }
    }
}
