import DanaKit
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
    struct PumpSetupView: UIViewControllerRepresentable, CompletionNotifying {
        let pumpIdentifier: String
        let pumpInitialSettings: PumpInitialSettings
        let deviceManager: DeviceDataManager
        let bluetoothManager: BluetoothStateManager
        weak var completionDelegate: CompletionDelegate?
        weak var onboardingDelegate: PumpManagerOnboardingDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
            // var setupViewController: PumpManagerSetupViewController & UIViewController & CompletionNotifying
//            var setupViewController: SetupUIResult<
//                PumpManagerViewController,
//                PumpManagerUI
//            >

            let initialSettings = PumpManagerSetupSettings(
                maxBasalRateUnitsPerHour: pumpInitialSettings.maxBasalRateUnitsPerHour,
                maxBolusUnits: pumpInitialSettings.maxBolusUnits,
                basalSchedule: pumpInitialSettings.basalSchedule
            )

            switch deviceManager.setupPumpManager(
                withIdentifier: pumpIdentifier,
                initialSettings: initialSettings,
                allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev],
                prefersToSkipUserInteraction: false
            ) {
            case let .failure(error):
                warning(
                    .deviceManager,
                    "Failure to setup pump manager with identifier '\(pumpIdentifier)': \(String(describing: error))"
                )
                return UIViewController()

            case let .success(success):
                switch success {
                case var .userInteractionRequired(setupViewControllerUI):
                    setupViewControllerUI.pumpManagerOnboardingDelegate = onboardingDelegate
                    setupViewControllerUI.completionDelegate = completionDelegate
                    return setupViewControllerUI
                case .createdAndOnboarded:
                    info(.deviceManager, "Pump manager with identifier '\(pumpIdentifier)' created and onboarded")

                    // TODO: [loopkit] device manager handles this case already, but better to double-check
//                    setupDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManagerUI)
                    completionDelegate?.completionNotifyingDidComplete(self)
                    return UIViewController()
                }
            }

//            switch setupViewController {
//            case var .userInteractionRequired(setupViewControllerUI):
//                setupViewControllerUI.pumpManagerOnboardingDelegate = setupDelegate
//                setupViewControllerUI.completionDelegate = completionDelegate
//                return setupViewControllerUI
//            // show(setupViewController, sender: self)
//            case let .createdAndOnboarded(pumpManagerUI):
//                debug(.default, "Pump manager  created and onboarded")
//                setupDelegate?.pumpManagerOnboarding(didCreatePumpManager: pumpManagerUI)
//                return UIViewController()
//            }

//            switch pumpType {
//            case .minimed:
//                setupViewController = MinimedPumpManager.setupViewController(
//                    initialSettings: initialSettings,
//                    bluetoothProvider: bluetoothManager,
//                    colorPalette: .default,
//                    allowDebugFeatures: false,
//                    prefersToSkipUserInteraction: false, // TODO: should this be true or false?
//                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
//                )
//            case .omnipod:
//                setupViewController = OmnipodPumpManager.setupViewController(
//                    initialSettings: initialSettings,
//                    bluetoothProvider: bluetoothManager,
//                    colorPalette: .default,
//                    allowDebugFeatures: false,
//                    prefersToSkipUserInteraction: false, // TODO: should this be true or false?
//                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
//                )
//            case .omnipodBLE:
//                setupViewController = OmniBLEPumpManager.setupViewController(
//                    initialSettings: initialSettings,
//                    bluetoothProvider: bluetoothManager,
//                    colorPalette: .default,
//                    allowDebugFeatures: false,
//                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
//                )
//            case .dana:
//                setupViewController = DanaKitPumpManager.setupViewController(
//                    initialSettings: initialSettings,
//                    bluetoothProvider: bluetoothManager,
//                    colorPalette: .default,
//                    allowDebugFeatures: false,
//                    prefersToSkipUserInteraction: false, // TODO: should this be true or false?
//                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
//                )
//            case .simulator:
//                setupViewController = MockPumpManager.setupViewController(
//                    initialSettings: initialSettings,
//                    bluetoothProvider: bluetoothManager,
//                    colorPalette: .default,
//                    allowDebugFeatures: false,
//                    prefersToSkipUserInteraction: false, // TODO: should this be true or false?
//                    allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
//                )
//            }

            // setupViewController.setupDelegate = setupDelegate
            // setupViewController.completionDelegate = completionDelegate
            // return setupViewController
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
