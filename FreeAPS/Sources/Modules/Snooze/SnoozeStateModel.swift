import SwiftUI

extension Snooze {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var userNotificationsManager: UserNotificationsManager!

        @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast

        func stopSound() async {
            await userNotificationsManager.stopSound()
        }
    }
}
