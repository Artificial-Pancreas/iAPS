import Foundation
import SwiftDate

protocol ProfileAndSettingsUploadManager: Sendable {
    func uploadProfileAndSettings(force: Bool) async
}

actor BaseProfileAndSettingsUploadManager: ProfileAndSettingsUploadManager, LifetimeOwner, AppService {
    private let storage: FileStorage
    private let settingsManager: SettingsManager
    private let nightscoutManager: NightscoutManager
    private let databaseManager: DatabaseManager
    private let appCoordinator: AppCoordinator
    private let statisticsFactory: DatabaseStatisticsFactory

    let lifetime = Lifetime()

    private let coreDataStorage = CoreDataStorage()

    private var lastVersionCheck: VNrSnapshot?

    private var latestUploadedStats: StatsDataSnapshot?

    init(
        storage: FileStorage,
        settingsManager: SettingsManager,
        nightscoutManager: NightscoutManager,
        databaseManager: DatabaseManager,
        appCoordinator: AppCoordinator,
        statisticsFactory: DatabaseStatisticsFactory
    ) {
        self.storage = storage
        self.settingsManager = settingsManager
        self.nightscoutManager = nightscoutManager
        self.databaseManager = databaseManager
        self.appCoordinator = appCoordinator
        self.statisticsFactory = statisticsFactory
    }

    // this is called at the start of the app
    func start() async {
        lastVersionCheck = await coreDataStorage.fetchVersion()
        latestUploadedStats = await coreDataStorage.fetchStats()
        observe(appCoordinator.loopCompleted) { me, _ in
            await me.versionCheck()
            await me.uploadStatistics()
            await me.databaseManager.retryPendingLogUpload()
        }
    }

    private func uploadStatistics() async {
        let newVersion = UserDefaults.standard.bool(forKey: IAPSconfig.newVersion)

        if !newVersion,
           let latestUploadedStats = self.latestUploadedStats,
           let latestStatsUploadDate = latestUploadedStats.lastrun,
           latestStatsUploadDate > Date.now.addingTimeInterval(-10.hours.timeInterval)
        {
            return
        }

        let settings = await settingsManager.settings

        if settings.uploadStats {
            let dailystat = await statisticsFactory.buildStats(settings: settings)
            await storage.save(dailystat, as: OpenAPS.Monitor.statistics)
            let profile = await statisticsFactory.buildProfile()
            await databaseManager.uploadStatistics(dailystat: dailystat, profile: profile)
        } else {
            let version = await statisticsFactory.buildVersion()
            await databaseManager.uploadVersion(version: version)
        }
        latestUploadedStats = await coreDataStorage.fetchStats()
    }

    func uploadProfileAndSettings(force: Bool) async {
        let settings = await settingsManager.settings
        guard settings.isUploadEnabled || settings.uploadStats || force else { return }
        let profile = await statisticsFactory.buildProfile()
        await nightscoutManager.uploadProfileAndSettings(profile: profile, force: force)
        await databaseManager.uploadProfileAndSettings(profile: profile, force: force)
    }

    private func versionCheck() async {
        if let lastVersionCheck = self.lastVersionCheck,
           let lastCheckDate = lastVersionCheck.date,
           lastCheckDate > Date.now.addingTimeInterval(-10.hours.timeInterval) { return }

        await databaseManager.fetchVersion()
        lastVersionCheck = await coreDataStorage.fetchVersion()
    }
}
