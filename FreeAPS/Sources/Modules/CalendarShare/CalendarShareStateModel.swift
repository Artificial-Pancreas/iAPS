import Foundation

import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI
import UIKit

extension CalendarShare {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var calendarManager: CalendarManager!

        @Published var createCalendarEvents = false
        @Published var displayCalendarIOBandCOB = false
        @Published var displayCalendarEmojis = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil

        override func subscribe() {
            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()

            subscribeSetting(\.useCalendar, on: $createCalendarEvents) { createCalendarEvents = $0 }
            subscribeSetting(\.displayCalendarIOBandCOB, on: $displayCalendarIOBandCOB) { displayCalendarIOBandCOB = $0 }
            subscribeSetting(\.displayCalendarEmojis, on: $displayCalendarEmojis) { displayCalendarEmojis = $0 }

            $createCalendarEvents
                .removeDuplicates()
                .flatMap { [weak self] ok -> AnyPublisher<Bool, Never> in
                    guard ok, let self = self else { return Just(false).eraseToAnyPublisher() }
                    return self.calendarManager.requestAccessIfNeeded()
                }
                .map { [weak self] ok -> [String] in
                    guard ok, let self = self else { return [] }
                    return self.calendarManager.calendarIDs()
                }
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.calendarIDs, on: self)
                .store(in: &lifetime)

            $currentCalendarID
                .removeDuplicates()
                .sink { [weak self] id in
                    guard id.isNotEmpty else {
                        self?.calendarManager.currentCalendarID = nil
                        return
                    }
                    self?.calendarManager.currentCalendarID = id
                }
                .store(in: &lifetime)
        }
    }
}
