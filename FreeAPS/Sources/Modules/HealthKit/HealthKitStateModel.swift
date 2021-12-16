import Combine
import SwiftUI

extension AppleHealthKit {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var healthKitManager: HealthKitManager!

        @Published var useAppleHealth = false
        @Published var needShowInformationTextForSetPermissions = false

        override func subscribe() {
            useAppleHealth = settingsManager.settings.useAppleHealth

            needShowInformationTextForSetPermissions = healthKitManager.areAllowAllPermissions

            subscribeSetting(\.useAppleHealth, on: $useAppleHealth) {
                useAppleHealth = $0
            } didSet: { [weak self] value in
                guard let self = self else { return }

                guard value else {
                    self.needShowInformationTextForSetPermissions = false
                    return
                }

                self.healthKitManager.requestPermission { _, error in
                    guard error == nil else {
                        return
                    }

                    debug(.service, "User set permission for HealthKitManager")

                    self.healthKitManager.createObserver()
                    self.healthKitManager.enableBackgroundDelivery()
                    DispatchQueue.main.async {
                        self.needShowInformationTextForSetPermissions = !self.healthKitManager.checkAvailabilitySaveBG()
                    }
                }
            }
        }
    }
}
