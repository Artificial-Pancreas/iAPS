import Foundation
import SwiftDate
import Swinject

protocol AnnouncementsStorage {
    func storeAnnouncements(_ announcements: [Announcement], enacted: Bool)
    func syncDate() -> Date
    func recent() -> Announcement?
    func validate() -> [Announcement]
    func recentEnacted() -> Announcement?
}

final class BaseAnnouncementsStorage: AnnouncementsStorage, Injectable {
    enum Config {
        static let recentInterval = 10.minutes.timeInterval
    }

    private let processQueue = DispatchQueue(label: "BaseAnnouncementsStorage.processQueue")
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeAnnouncements(_ announcements: [Announcement], enacted: Bool) {
        processQueue.sync {
            let file = enacted ? OpenAPS.FreeAPS.announcementsEnacted : OpenAPS.FreeAPS.announcements
            self.storage.transaction { storage in
                storage.append(announcements, to: file, uniqBy: \.createdAt)
                let uniqEvents = storage.retrieve(file, as: [Announcement].self)?
                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.createdAt > $1.createdAt } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
        }
    }

    func syncDate() -> Date {
        guard let events = storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self),
              let recentEnacted = events.filter({ $0.enteredBy == Announcement.remote }).first
        else {
            return Date().addingTimeInterval(-Config.recentInterval)
        }
        return recentEnacted.createdAt.addingTimeInterval(Config.recentInterval)
    }

    func recent() -> Announcement? {
        guard let events = storage.retrieve(OpenAPS.FreeAPS.announcements, as: [Announcement].self)
        else {
            return nil
        }
        guard let recent = events
            .filter({
                $0.enteredBy == Announcement.remote && $0.createdAt.addingTimeInterval(Config.recentInterval) > Date()
            })
            .first
        else {
            return nil
        }
        guard let enactedEvents = storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self)
        else {
            return recent
        }

        guard enactedEvents.first(where: { $0.createdAt == recent.createdAt }) == nil
        else {
            return nil
        }
        return recent
    }

    func recentEnacted() -> Announcement? {
        guard let enactedEvents = storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self)
        else {
            return nil
        }
        let enactedEventsLast = enactedEvents.first

        if -1 * (enactedEventsLast?.createdAt ?? .distantPast).timeIntervalSinceNow.minutes <= 10 {
            return enactedEventsLast
        }
        return nil
    }

    func validate() -> [Announcement] {
        guard let enactedEvents = storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self)?.reversed()
        else {
            return []
        }
        let validate = enactedEvents
            .filter({ $0.enteredBy == Announcement.remote })
        return validate
    }
}
