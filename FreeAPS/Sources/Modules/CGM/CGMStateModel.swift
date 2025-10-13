import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!

        @Published var cgmSetupPresented: Bool = false
        @Published var cgmSettingsPresented: Bool = false
        @Published private(set) var cgmIdentifierToSetUp: String? = nil

        @Published var smoothGlucose = false
        @Published var sensorDays: Double = 10

        override func subscribe() {
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
            subscribeSetting(\.sensorDays, on: $sensorDays) { sensorDays = $0 }
        }

        func removePumpAsCGM() {
            deviceManager.removePumpAsCGM()
        }

        func setupCGM(_ identifier: String?) {
            cgmIdentifierToSetUp = identifier
            cgmSetupPresented = identifier != nil && deviceManager.cgmManager == nil
            cgmSettingsPresented = identifier != nil && deviceManager.cgmManager?.pluginIdentifier == identifier && deviceManager
                .cgmManager?.isOnboarded == true
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task { @MainActor in
            setupCGM(nil)
        }
    }
}
