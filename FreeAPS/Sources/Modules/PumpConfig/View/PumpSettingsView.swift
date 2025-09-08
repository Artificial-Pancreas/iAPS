import LoopKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSettingsView: UIViewControllerRepresentable {
        let pumpManager: PumpManagerUI
        let bluetoothManager: BluetoothStateManager
        weak var completionDelegate: CompletionDelegate?
        weak var onboardingDelegate: PumpManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSettingsView>) -> UIViewController {
            var vc = pumpManager.settingsViewController(
                bluetoothProvider: bluetoothManager,
                colorPalette: .default,
                // TODO: [loopkit] not sure debug should be true, but with false - pump simulator settings are not available, cannot remove once added
                allowDebugFeatures: true,
                allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
            )
            vc.pumpManagerOnboardingDelegate = onboardingDelegate
            vc.completionDelegate = completionDelegate
            return vc
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSettingsView>) {}
    }
}
