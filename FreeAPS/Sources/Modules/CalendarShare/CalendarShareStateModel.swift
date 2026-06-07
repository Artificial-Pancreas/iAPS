import Combine
import Foundation
import SwiftUI

extension CalendarShare {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var calendarManager: CalendarManager!

        @Published var createCalendarEvents = false
        @Published var displayCalendarIOBandCOB = false
        @Published var displayCalendarEmojis = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil

        override func subscribe() async {
            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = await calendarManager.calendarIDs()

            subscribeSetting(
                \.useCalendar,
                on: $createCalendarEvents,
                initial: { self.createCalendarEvents = $0 },
                didSet: { [weak self] enabled in
                    Task { [weak self] in
                        guard let self else { return }
                        guard enabled, await self.calendarManager.requestAccessIfNeeded() else {
                            self.calendarIDs = []
                            return
                        }
                        self.calendarIDs = await self.calendarManager.calendarIDs()
                    }
                }
            )

            subscribeSetting(\.displayCalendarIOBandCOB, on: $displayCalendarIOBandCOB) { self.displayCalendarIOBandCOB = $0 }
            subscribeSetting(\.displayCalendarEmojis, on: $displayCalendarEmojis) { self.displayCalendarEmojis = $0 }

            $currentCalendarID
                .removeDuplicates()
                .sink { [weak self] id in
                    Task { [weak self] in
                        guard let self else { return }
                        await self.calendarManager.setCurrentCalendarID(id.isNotEmpty ? id : nil)
                    }
                }
                .store(in: lifetime)
        }
    }
}
