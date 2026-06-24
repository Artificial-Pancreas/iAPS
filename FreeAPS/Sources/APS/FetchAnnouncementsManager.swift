import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchAnnouncementsManager {}

actor BaseFetchAnnouncementsManager: FetchAnnouncementsManager, LifetimeOwner, AppService {
    private let announcementsStorage: AnnouncementsStorage
    private let nightscoutManager: NightscoutManager
    private let apsManager: APSManager
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

    private let interval: TimeInterval = .minutes(4)
    private var pollingTask: Task<Void, Never>?
    private var fetchEnabled = false

    init(
        announcementsStorage: AnnouncementsStorage,
        nightscoutManager: NightscoutManager,
        apsManager: APSManager,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator
    ) {
        self.announcementsStorage = announcementsStorage
        self.nightscoutManager = nightscoutManager
        self.apsManager = apsManager
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
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
        let settings = await self.settingsManager.settings
        guard settings.allowAnnouncements else {
            return
        }
        await withBackgroundTask("fetch announcements") {
            debug(.nightscout, "FetchAnnouncementsManager heartbeat")
            debug(
                .nightscout,
                "Start fetching announcements, time: \(Date.now.formatted(date: .omitted, time: .shortened))"
            ) // Add timestamp for debugging of the remote command delay

            let announcements = await nightscoutManager.fetchAnnouncements()

            let futureEntries = announcements.filter({ $0.createdAt > Date.now })
            // Delete future entries
            if !futureEntries.isEmpty {
                debug(.nightscout, "Future Announcements found")
                await nightscoutManager.deleteAnnouncements()
            }

            guard let last = announcements
                .filter({ $0.createdAt < Date.now })
                .sorted(by: { $0.createdAt < $1.createdAt })
                .last
            else { return }

            await announcementsStorage.storeAnnouncements([last], enacted: false)

            if let recent = await announcementsStorage.recent(), recent.action != nil
            {
                debug(
                    .nightscout,
                    "New announcements found, time: \(Date.now.formatted(date: .omitted, time: .shortened))"
                ) // Add timestamp for debugging of remote commnand delay
                await apsManager.enactAnnouncement(recent)
            }
        }
    }
}
