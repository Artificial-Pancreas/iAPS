import SwiftUI

extension NotificationsConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var settingsManager: SettingsManager!

        @Published var glucoseBadge = false

        override func subscribe() {
            glucoseBadge = settingsManager.settings.glucoseBadge

            $glucoseBadge
                .removeDuplicates()
                .assign(to: \.settings.glucoseBadge, on: settingsManager)
                .store(in: &lifetime)
        }

        deinit {
            print("OK")
        }
    }
}
