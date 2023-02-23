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

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            let displayGlucoseUnitObservable: DisplayGlucoseUnitObservable
            switch unit {
            case .mgdL:
                displayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .milligramsPerDeciliter)
            case .mmolL:
                displayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .millimolesPerLiter)
            }

            var vc = cgmManager.settingsViewController(
                bluetoothProvider: bluetoothManager,
                displayGlucoseUnitObservable: displayGlucoseUnitObservable,
                colorPalette: .default,
                allowDebugFeatures: false
            )
            // vc.cgmManagerOnboardingDelegate =
            // vc.completionDelegate = self
            vc.completionDelegate = completionDelegate

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
