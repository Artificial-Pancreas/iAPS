import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSettingsView: UIViewControllerRepresentable {
        let cgmManager: CGMManagerUI
        let bluetoothManager: BluetoothStateManager
        let unit: GlucoseUnits
        weak var completionDelegate: CompletionDelegate?
        weak var onboardingDelegate: CGMManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            // TODO: [loopkit] inject DisplayGlucosePreference from assembly
            let displayGlucoseUnitObservable: DisplayGlucosePreference
            switch unit {
            case .mgdL:
                displayGlucoseUnitObservable = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
            case .mmolL:
                displayGlucoseUnitObservable = DisplayGlucosePreference(displayGlucoseUnit: .millimolesPerLiter)
            }

            var vc = cgmManager.settingsViewController(
                bluetoothProvider: bluetoothManager,
                displayGlucosePreference: displayGlucoseUnitObservable,
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
