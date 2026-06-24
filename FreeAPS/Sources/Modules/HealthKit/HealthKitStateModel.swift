import Combine
import SwiftUI

extension AppleHealthKit {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var healthKitManager: HealthKitManager!

        @Published var useAppleHealth = false
        @Published var needShowInformationTextForSetPermissions = false

        override func subscribe() async {
            needShowInformationTextForSetPermissions = await healthKitManager.areAllowAllPermissions

            subscribeSetting(\.useAppleHealth, on: $useAppleHealth) {
                self.useAppleHealth = $0
            } didSet: { [weak self] value in
                guard let self else { return }

                guard value else {
                    self.needShowInformationTextForSetPermissions = false
                    return
                }

                do {
                    let granted = try await self.healthKitManager.requestPermission()
                    if granted {
                        debug(.service, "Permission granted for HealthKitManager")
                    } else {
                        debug(.service, "Permission not granted for HealthKitManager")
                    }
                } catch {
                    warning(.service, "Permission not granted for HealthKitManager", error: error)
                }
                self.needShowInformationTextForSetPermissions = await !self.healthKitManager.checkAvailabilitySaveBG()
            }
        }
    }
}
