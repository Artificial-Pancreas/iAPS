import Combine
import Foundation
import SwiftDate
import Swinject

protocol FetchAnnouncementsManager {}

final class BaseFetchAnnouncementsManager: FetchAnnouncementsManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseFetchAnnouncementsManager.processQueue")
    @Injected() var announcementsStorage: AnnouncementsStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!
    @Injected() var settingsManager: SettingsManager!

    private var lifetime = Set<AnyCancellable>()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { _ -> AnyPublisher<[Announcement], Never> in
                guard self.settingsManager.settings.allowAnnouncements else {
                    return Just([]).eraseToAnyPublisher()
                }
                debug(.nightscout, "FetchAnnouncementsManager heartbeat")
                debug(.nightscout, "Start fetching announcements")
                return self.nightscoutManager.fetchAnnouncements()
            }
            .sink { announcements in
                guard announcements.filter({ $0.createdAt > self.announcementsStorage.syncDate() }).isNotEmpty else { return }
                self.announcementsStorage.storeAnnouncements(announcements, enacted: false)
                if self.settingsManager.settings.allowAnnouncements, let recent = self.announcementsStorage.recent(),
                   recent.action != nil
                {
                    debug(.nightscout, "New announcements found")
                    self.apsManager.enactAnnouncement(recent)
                }
            }
            .store(in: &lifetime)
        timer.resume()
    }
}
