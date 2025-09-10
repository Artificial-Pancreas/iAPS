import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSettingsView: UIViewControllerRepresentable {
        let cgmManager: CGMManagerUI
        let bluetoothManager: BluetoothStateManager
        let displayGlucosePreference: DisplayGlucosePreference
        weak var completionDelegate: CompletionDelegate?
        weak var onboardingDelegate: CGMManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            var vc = cgmManager.settingsViewController(
                bluetoothProvider: bluetoothManager,
                displayGlucosePreference: displayGlucosePreference,
                colorPalette: .default,
                allowDebugFeatures: true
            )
            vc.completionDelegate = completionDelegate
            vc.cgmManagerOnboardingDelegate = onboardingDelegate

            return vc
        }

        func updateUIViewController(
            _ uiViewController: UIViewController,
            context _: UIViewControllerRepresentableContext<CGMSettingsView>
        ) {
            uiViewController.isModalInPresentation = true
        }
    }
}
