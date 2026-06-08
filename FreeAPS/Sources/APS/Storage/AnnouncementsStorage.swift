import Foundation
import SwiftDate
import Swinject

protocol AnnouncementsStorage: Sendable {
    func storeAnnouncements(_ announcements: [Announcement], enacted: Bool) async
    func syncDate() async -> Date
    func recent() async -> Announcement?
    func validate() async -> [Announcement]
    func recentEnacted() async -> Announcement?
}

actor BaseAnnouncementsStorage: AnnouncementsStorage {
    enum Config {
        static let recentInterval = 10.minutes.timeInterval
    }

    private let storage: FileStorage

    init(
        storage: FileStorage
    ) {
        self.storage = storage
    }

    func storeAnnouncements(_ announcements: [Announcement], enacted: Bool) async {
        let file = enacted ? OpenAPS.FreeAPS.announcementsEnacted : OpenAPS.FreeAPS.announcements
        await self.storage.appendAndModify(announcements, to: file, uniqBy: \.createdAt) {
            $0
                .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                .sorted { $0.createdAt > $1.createdAt }
        }
    }

    func syncDate() async -> Date {
        guard let events = await storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self),
              let recentEnacted = events.filter({ $0.enteredBy == Announcement.remote }).first
        else {
            return Date().addingTimeInterval(-Config.recentInterval)
        }
        return recentEnacted.createdAt.addingTimeInterval(Config.recentInterval)
    }

    func recent() async -> Announcement? {
        guard let events = await storage.retrieve(OpenAPS.FreeAPS.announcements, as: [Announcement].self)
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
        guard let enactedEvents = await storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self)
        else {
            return recent
        }

        guard enactedEvents.first(where: { $0.createdAt == recent.createdAt }) == nil
        else {
            return nil
        }
        return recent
    }

    func recentEnacted() async -> Announcement? {
        guard let enactedEvents = await storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self)
        else {
            return nil
        }
        let enactedEventsLast = enactedEvents.first

        if -1 * (enactedEventsLast?.createdAt ?? .distantPast).timeIntervalSinceNow.minutes <= 10 {
            return enactedEventsLast
        }
        return nil
    }

    func validate() async -> [Announcement] {
        let enactedEvents = await storage.retrieve(OpenAPS.FreeAPS.announcementsEnacted, as: [Announcement].self)?
            .reversed() ?? []
        return enactedEvents.filter({ $0.enteredBy == Announcement.remote })
    }
}
