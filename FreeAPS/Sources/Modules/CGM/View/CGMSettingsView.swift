import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSettingsView: UIViewControllerRepresentable {
        let cgmManager: CGMManagerUI
        let deviceManager: DeviceDataManager
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSettingsView>) -> UIViewController {
            var vc = deviceManager.cgmManagerSettingsView(cgmManager: cgmManager)
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
