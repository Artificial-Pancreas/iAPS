import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSettingsView: UIViewControllerRepresentable, CompletionNotifying {
        let deviceManager: DeviceDataManager
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            guard var vc = deviceManager.cgmManagerSettingsView() else {
                // race condition (extremely unlikely to ever happen): CGM manager got removed right after the user tapped the button but before the UI got built here
                warning(.deviceManager, "CGM manager was removed")
                DispatchQueue.main.async { [completionDelegate] in
                    completionDelegate?.completionNotifyingDidComplete(self)
                }
                return UIViewController()
            }
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
