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
    struct PumpSettingsView: UIViewControllerRepresentable {
        let pumpManager: PumpManagerUI
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSettingsView>) -> UIViewController {
            var vc = pumpManager.settingsViewController()
            vc.completionDelegate = completionDelegate
            return vc
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSettingsView>) {}
    }
}
