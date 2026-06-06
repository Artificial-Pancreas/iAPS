import Foundation
import SwiftDate
import Swinject

protocol ProfileAndSettingsUploadManager: Sendable {
    func uploadProfileAndSettings(force: Bool) async
}

actor BaseProfileAndSettingsUploadManager: ProfileAndSettingsUploadManager, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var nightscoutManager: NightscoutManager!
    @Injected() private var databaseManager: DatabaseManager!
    @Injected() private var appCoordinator: AppCoordinator!

    @Injected() private var statisticsFactory: DatabaseStatisticsFactory!

    private var lifetime = Lifetime()

    private let coreDataStorage = CoreDataStorage()

    private var lastVersionCheck: VNr?

    private var latestUploadedStats: StatsData?

    init(resolver: Resolver) {
        injectServices(resolver)
        Task {
            await subscribe()
        }
    }

    private func subscribe() async {
        lastVersionCheck = coreDataStorage.fetchVersion()
        latestUploadedStats = coreDataStorage.fetchStats()
        observe(appCoordinator.loopCompleted, in: &lifetime) { _ in
            await self.versionCheck()
            await self.uploadStatistics()
            await self.databaseManager.retryPendingLogUpload()
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
        latestUploadedStats = coreDataStorage.fetchStats()
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
        lastVersionCheck = coreDataStorage.fetchVersion()
    }
}
