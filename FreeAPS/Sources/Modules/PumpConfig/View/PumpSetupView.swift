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
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
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
                    setupViewControllerUI.completionDelegate = completionDelegate
                    return setupViewControllerUI
                case .createdAndOnboarded:
                    debug(.deviceManager, "Pump manager with identifier '\(pumpIdentifier)' created and onboarded")
                    completionDelegate?.completionNotifyingDidComplete(self)
                    return UIViewController()
                }
            }
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
