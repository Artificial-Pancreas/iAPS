import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var appCoordinator: AppCoordinator!

        @Published var cgmSetupPresented: Bool = false
        @Published var cgmSettingsPresented: Bool = false
        @Published private(set) var cgmIdentifierToSetUp: String? = nil

        @Published var smoothGlucose = false
        @Published var sensorDays: Double = 10

        override func subscribe() async {
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose) { self.smoothGlucose = $0 }
            subscribeSetting(\.sensorDays, on: $sensorDays) { self.sensorDays = $0 }
        }

        func removePumpAsCGM() {
            deviceManager.removePumpAsCGM()
        }

        func setupNewCgm(_ identifier: String?) {
            cgmIdentifierToSetUp = identifier
            cgmSetupPresented = true
            cgmSettingsPresented = false
        }

        func showCurrentCgmSettings() {
            guard let cgmInfo = appCoordinator.cgmInfo.value else { return }

            if cgmInfo.isOnboarded {
                cgmIdentifierToSetUp = nil
                cgmSetupPresented = false
                cgmSettingsPresented = true
            } else {
                // CGM is set up but not fully onboarded, start the setup for the same CGM manager from scratch
                setupNewCgm(cgmInfo.identifier)
            }
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task { @MainActor in
            if cgmSetupPresented {
                cgmSetupPresented = false
                cgmIdentifierToSetUp = nil

                // present settings after setup
                // TODO: will this have propagated already, after setup is complete?
                cgmSettingsPresented = appCoordinator.cgmInfo.value?.isOnboarded == true
            } else if cgmSettingsPresented {
                cgmSetupPresented = false
                cgmSettingsPresented = false
                cgmIdentifierToSetUp = nil
            }
        }
    }
}
