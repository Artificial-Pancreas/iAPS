import SwiftUI

extension NotificationsConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var glucoseBadge = false
        @Published var glucoseNotificationsAlways = false

        override func subscribe() {
            glucoseBadge = settingsManager.settings.glucoseBadge
            glucoseNotificationsAlways = settingsManager.settings.glucoseNotificationsAlways

            subscribeSetting(\.glucoseBadge, on: $glucoseBadge)
            subscribeSetting(\.glucoseNotificationsAlways, on: $glucoseNotificationsAlways)
        }
    }
}
