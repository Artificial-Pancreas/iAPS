import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchAnnouncementsManager {}

actor BaseFetchAnnouncementsManager: FetchAnnouncementsManager, Injectable, LifetimeOwner {
    @Injected() var announcementsStorage: AnnouncementsStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var appCoordinator: AppCoordinator!

    let lifetime = Lifetime()

    private let interval: TimeInterval = .minutes(4)
    private var pollingTask: Task<Void, Never>?
    private var fetchEnabled = false

    init(resolver: Resolver) {
        injectServices(resolver)
        Task {
            await self.subscribe()
        }
    }

    private func subscribe() async {
        let settings = await settingsManager.settings
        settingsUpdated(settings)

        observe(appCoordinator.settingsUpdates) { me, settings in
            await me.settingsUpdated(settings)
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
        let settings = await self.settingsManager.settings
        guard settings.allowAnnouncements else {
            return
        }
        debug(.nightscout, "FetchAnnouncementsManager heartbeat")
        debug(
            .nightscout,
            "Start fetching announcements, time: \(Date.now.formatted(date: .omitted, time: .shortened))"
        ) // Add timestamp for debugging of the remote command delay

        let announcements = await self.nightscoutManager.fetchAnnouncements()

        let futureEntries = announcements.filter({ $0.createdAt > Date.now })
        // Delete future entries
        if !futureEntries.isEmpty {
            debug(.nightscout, "Future Announcements found")
            await self.nightscoutManager.deleteAnnouncements()
        }

        guard let last = announcements
            .filter({ $0.createdAt < Date.now })
            .sorted(by: { $0.createdAt < $1.createdAt })
            .last
        else { return }

        await self.announcementsStorage.storeAnnouncements([last], enacted: false)

        if let recent = await self.announcementsStorage.recent(), recent.action != nil
        {
            debug(
                .nightscout,
                "New announcements found, time: \(Date.now.formatted(date: .omitted, time: .shortened))"
            ) // Add timestamp for debugging of remote commnand delay
            await self.apsManager.enactAnnouncement(recent)
        }
    }
}
