import LoopKit
import LoopKitUI
import MinimedKit
import MinimedKitUI
import OmniKitUI
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSetupView: UIViewControllerRepresentable {
        let pumpType: PumpType
        let deviceProvider: RileyLinkDeviceProvider
        weak var completionDelegate: CompletionDelegate?
        weak var setupDelegate: PumpManagerSetupViewControllerDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSetupView>) -> UIViewController {
            var setupViewController: PumpManagerSetupViewController & UIViewController & CompletionNotifying

            switch pumpType {
            case .minimed:
                setupViewController = UIStoryboard(
                    name: "MinimedPumpManager",
                    bundle: Bundle(for: MinimedPumpManagerSetupViewController.self)
                ).instantiateViewController(withIdentifier: "DevelopmentPumpSetup") as! MinimedPumpManagerSetupViewController
            case .omnipod:
                setupViewController = UIStoryboard(
                    name: "OmnipodPumpManager",
                    bundle: Bundle(for: OmnipodPumpManagerSetupViewController.self)
                ).instantiateViewController(withIdentifier: "DevelopmentPumpSetup") as! OmnipodPumpManagerSetupViewController
            }
            if let rileyLinkManagerViewController = setupViewController as? RileyLinkManagerSetupViewController {
                rileyLinkManagerViewController
                    .rileyLinkPumpManager = RileyLinkPumpManager(rileyLinkDeviceProvider: deviceProvider)
            }
            setupViewController.setupDelegate = setupDelegate
            setupViewController.completionDelegate = completionDelegate
            return setupViewController
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSetupView>) {}
    }
}
