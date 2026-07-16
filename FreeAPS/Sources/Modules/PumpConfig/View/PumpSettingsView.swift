import LoopKitUI
import SwiftUI
import UIKit

extension PumpConfig {
    struct PumpSettingsView: UIViewControllerRepresentable, CompletionNotifying {
        let deviceManager: DeviceDataManager
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<PumpSettingsView>) -> UIViewController {
            guard var vc = deviceManager.pumpManagerSettingsView() else {
                // race condition (extremely unlikely to ever happen): pump manager got removed right after the user tapped the button but before the UI got built here
                warning(.deviceManager, "Pump manager was removed")
                DispatchQueue.main.async { [completionDelegate] in
                    completionDelegate?.completionNotifyingDidComplete(self)
                }
                return UIViewController()
            }
            vc.completionDelegate = completionDelegate

            return vc
        }

        func updateUIViewController(_: UIViewController, context _: UIViewControllerRepresentableContext<PumpSettingsView>) {}
    }
}
