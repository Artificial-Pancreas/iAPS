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

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 4.minutes.timeInterval)

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
                debug(
                    .nightscout,
                    "Start fetching announcements, time: \(Date.now.formatted(date: .omitted, time: .shortened))"
                ) // Add timestamp for debugging of the remote command delay
                return self.nightscoutManager.fetchAnnouncements()
            }
            .sink { announcements in
                let futureEntries = announcements.filter({ $0.createdAt > Date.now })
                // Delete future entries
                if !futureEntries.isEmpty {
                    debug(.nightscout, "Future Announcements found")
                    self.nightscoutManager.deleteAnnouncements()
                }

                guard let last = announcements
                    .filter({ $0.createdAt < Date.now })
                    .sorted(by: { $0.createdAt < $1.createdAt })
                    .last
                else { return }

                self.announcementsStorage.storeAnnouncements([last], enacted: false)

                if self.settingsManager.settings.allowAnnouncements, let recent = self.announcementsStorage.recent(),
                   recent.action != nil
                {
                    debug(
                        .nightscout,
                        "New announcements found, time: \(Date.now.formatted(date: .omitted, time: .shortened))"
                    ) // Add timestamp for debugging of remote commnand delay
                    self.apsManager.enactAnnouncement(recent)
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }
}
