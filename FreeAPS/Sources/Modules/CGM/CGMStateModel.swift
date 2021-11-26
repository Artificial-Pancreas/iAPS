import Combine
import SwiftUI

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var libreSource: LibreTransmitterSource!
        @Injected() var calendarManager: CalendarManager!

        @Published var cgm: CGMType = .nightscout
        @Published var transmitterID = ""
        @Published var uploadGlucose = false
        @Published var createCalendarEvents = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil

        override func subscribe() {
            cgm = settingsManager.settings.cgm
            uploadGlucose = settingsManager.settings.uploadGlucose
            transmitterID = UserDefaults.standard.dexcomTransmitterID ?? ""
            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()
            createCalendarEvents = settingsManager.settings.useCalendar

            $cgm
                .removeDuplicates()
                .sink { [weak self] value in
                    guard let self = self else { return }
                    self.settingsManager.settings.cgm = value
                }
                .store(in: &lifetime)

            subscribeSetting(\.uploadGlucose, on: $uploadGlucose)

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

            subscribeSetting(\.useCalendar, on: $createCalendarEvents)

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

        func onChangeID() {
            UserDefaults.standard.dexcomTransmitterID = transmitterID
        }
    }
}
