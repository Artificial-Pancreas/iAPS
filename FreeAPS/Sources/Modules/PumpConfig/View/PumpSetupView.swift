import LoopKit
import LoopKitUI
import MinimedKit
import MinimedKitUI
import MockKit
import MockKitUI
import OmniBLE
import OmniKit
import OmniKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSetupView: UIViewControllerRepresentable {
        let pumpType: PumpType
        let pumpInitialSettings: PumpInitialSettings
        let bluetoothManager: BluetoothStateManager
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: PumpManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
            // var setupViewController: PumpManagerSetupViewController & UIViewController & CompletionNotifying
            var setupViewController: SetupUIResult<
                PumpManagerViewController,
                PumpManagerUI
            >

            let initialSettings = PumpManagerSetupSettings(
                maxBasalRateUnitsPerHour: pumpInitialSettings.maxBasalRateUnitsPerHour,
                maxBolusUnits: pumpInitialSettings.maxBolusUnits,
                basalSchedule: pumpInitialSettings.basalSchedule
            )

            switch pumpType {
            case .minimed:
                setupViewController = MinimedPumpManager.setupViewController(
                    initialSettings: initialSettings,
                    bluetoothProvider: bluetoothManager,
                    colorPalette: .default,
                    allowDebugFeatures: false,
                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev, .afrezza]
                )
            case .omnipod:
                setupViewController = OmnipodPumpManager.setupViewController(
                    initialSettings: initialSettings,
                    bluetoothProvider: bluetoothManager,
                    colorPalette: .default,
                    allowDebugFeatures: false,
                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev, .afrezza]
                )
            case .omnipodBLE:
                setupViewController = OmniBLEPumpManager.setupViewController(
                    initialSettings: initialSettings,
                    bluetoothProvider: bluetoothManager,
                    colorPalette: .default,
                    allowDebugFeatures: false,
                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev, .afrezza]
                )
            case .simulator:
                setupViewController = MockPumpManager.setupViewController(
                    initialSettings: initialSettings,
                    bluetoothProvider: bluetoothManager,
                    colorPalette: .default,
                    allowDebugFeatures: false,
                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev, .afrezza]
                )
            }

            // setupViewController.setupDelegate = setupDelegate
            // setupViewController.completionDelegate = completionDelegate
            // return setupViewController

            switch setupViewController {
            case var .userInteractionRequired(setupViewControllerUI):
                setupViewControllerUI.pumpManagerOnboardingDelegate = setupDelegate
                setupViewControllerUI.completionDelegate = completionDelegate
                return setupViewControllerUI
            // show(setupViewController, sender: self)
            case .createdAndOnboarded:
                debug(.default, "Pump manager  created and onboarded")
                return UIViewController() // TODO:
            }
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
