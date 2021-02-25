import LoopKit
import LoopKitUI
import MinimedKit
import MinimedKitUI
import OmniKit
import OmniKitUI
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSetupView: UIViewControllerRepresentable {
        let pumpType: PumpType
        let pumpInitialSettings: PumpInitialSettings
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: PumpManagerSetupViewControllerDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
            var setupViewController: PumpManagerSetupViewController & UIViewController & CompletionNotifying

            switch pumpType {
            case .minimed:
                setupViewController = MinimedPumpManager.setupViewController()
            case .omnipod:
                setupViewController = OmnipodPumpManager.setupViewController()
            }

            setupViewController.setupDelegate = setupDelegate
            setupViewController.completionDelegate = completionDelegate
            setupViewController.maxBolusUnits = pumpInitialSettings.maxBolusUnits
            setupViewController.maxBasalRateUnitsPerHour = pumpInitialSettings.maxBasalRateUnitsPerHour
            setupViewController.basalSchedule = pumpInitialSettings.basalSchedule
            return setupViewController
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
