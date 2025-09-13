import LoopKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSettingsView: UIViewControllerRepresentable {
        let pumpManager: PumpManagerUI
        let deviceManager: DeviceDataManager
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSettingsView>) -> UIViewController {
            var vc = deviceManager.pumpManagerSettingsView(pumpManager: pumpManager)
            vc.completionDelegate = completionDelegate
            return vc
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSettingsView>) {}
    }
}
