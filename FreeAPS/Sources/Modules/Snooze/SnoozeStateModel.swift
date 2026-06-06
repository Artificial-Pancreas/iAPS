import SwiftUI

extension Snooze {
    final class StateModel: BaseStateModel<Provider> {
        @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
        @Injected() private var glucoseStorage: GlucoseStorage!

        @Published var alarm: GlucoseAlarm?

        override func subscribe() async {
            alarm = await glucoseStorage.getAlarm()
        }
    }
}
