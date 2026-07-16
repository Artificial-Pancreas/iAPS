import SwiftUI

extension Snooze {
    final class StateModel: BaseStateModel<Provider> {
        @Persisted(key: "UserNotificationsManager.snoozeUntilDate") var snoozeUntilDate: Date = .distantPast
    }
}
