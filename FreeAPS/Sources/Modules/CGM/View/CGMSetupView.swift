import CGMBLEKit
import CGMBLEKitUI
import G7SensorKit
import G7SensorKitUI
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSetupView: UIViewControllerRepresentable {
        let CGMType: CGMType
        let bluetoothManager: BluetoothStateManager
        let unit: GlucoseUnits
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: CGMManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSetupView>) -> UIViewController {
            var setupViewController: SetupUIResult<
                CGMManagerViewController,
                CGMManagerUI
            >?

            let displayGlucoseUnitObservable: DisplayGlucoseUnitObservable
            switch unit {
            case .mgdL:
                displayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .milligramsPerDeciliter)
            case .mmolL:
                displayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .millimolesPerLiter)
            }

            switch CGMType {
            case .dexcomG5:
                setupViewController = G5CGMManager.setupViewController(
                    bluetoothProvider: bluetoothManager,
                    displayGlucoseUnitObservable: displayGlucoseUnitObservable,
                    colorPalette: .default,
                    allowDebugFeatures: false
                )
            case .dexcomG6:
                setupViewController = G6CGMManager.setupViewController(
                    bluetoothProvider: bluetoothManager,
                    displayGlucoseUnitObservable: displayGlucoseUnitObservable,
                    colorPalette: .default,
                    allowDebugFeatures: false
                )
            case .dexcomG7:
                setupViewController =
                    G7CGMManager.setupViewController(
                        bluetoothProvider: bluetoothManager,
                        displayGlucoseUnitObservable: displayGlucoseUnitObservable,
                        colorPalette: .default,
                        allowDebugFeatures: false
                    )
            default:
                break
            }

            switch setupViewController {
            case var .userInteractionRequired(setupViewControllerUI):
                setupViewControllerUI.cgmManagerOnboardingDelegate = setupDelegate
                setupViewControllerUI.completionDelegate = completionDelegate
                return setupViewControllerUI
            case let .createdAndOnboarded(cgmManagerUI):
                debug(.default, "CGM manager  created and onboarded")
                setupDelegate?.cgmManagerOnboarding(didCreateCGMManager: cgmManagerUI)
                return UIViewController()
            case .none:
                return UIViewController()
            }
        }

        func updateUIViewController(
            _ uiViewController: UIViewController,
            context _: UIViewControllerRepresentableContext<CGMSetupView>
        ) {
            uiViewController.isModalInPresentation = true
        }
    }
}
