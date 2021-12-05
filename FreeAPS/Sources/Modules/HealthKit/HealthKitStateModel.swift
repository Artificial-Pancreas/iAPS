import Combine
import SwiftUI

extension AppleHealthKit {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var healthKitManager: HealthKitManager!

        @Published var useAppleHealth = false
        @Published var needShowInformationTextForSetPermissions = false

        override func subscribe() {
            useAppleHealth = settingsManager.settings.useAppleHealth
            needShowInformationTextForSetPermissions = settingsManager.settings.needShowInformationTextForSetPermissions

            subscribeSetting(\.needShowInformationTextForSetPermissions, on: $needShowInformationTextForSetPermissions) { _ in }

            $useAppleHealth
                .removeDuplicates()
                .sink { [weak self] value in
                    guard let self = self else { return }
                    guard value else {
                        self.settingsManager.settings.useAppleHealth = false
                        self.needShowInformationTextForSetPermissions = false
                        return
                    }

                    self.healthKitManager.requestPermission { status, error in
                        guard error == nil else {
                            return
                        }
                        self.settingsManager.settings.useAppleHealth = status
                        self.healthKitManager.enableBackgroundDelivery()
                        self.healthKitManager.createObserver()
                        DispatchQueue.main.async {
                            if !self.healthKitManager.areAllowAllPermissions {
                                self.needShowInformationTextForSetPermissions = true
                            }
                        }
                    }
                }
                .store(in: &lifetime)
        }
    }
}
