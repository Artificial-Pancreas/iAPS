import CGMBLEKit
import CGMBLEKitUI
import G7SensorKit
import G7SensorKitUI
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    struct CGMSetupView: UIViewControllerRepresentable, CompletionNotifying {
        let cgmIdentifier: String
        let deviceManager: DeviceDataManager
//        let bluetoothManager: BluetoothStateManager
//        let unit: GlucoseUnits
        weak var completionDelegate: CompletionDelegate?

        func makeUIViewController(context _: UIViewControllerRepresentableContext<CGMSetupView>) -> UIViewController {
            switch deviceManager.setupCGMManager(withIdentifier: cgmIdentifier, prefersToSkipUserInteraction: false) {
            case let .failure(error):
                warning(
                    .deviceManager,
                    "Failure to setup CGM manager with identifier '\(cgmIdentifier)': \(String(describing: error))"
                )
                return UIViewController()
            case let .success(success):
                switch success {
                case var .userInteractionRequired(setupViewControllerUI):
                    setupViewControllerUI.completionDelegate = completionDelegate
                    return setupViewControllerUI
                case .createdAndOnboarded:
                    debug(.deviceManager, "CGM manager with identifier '\(cgmIdentifier)' created and onboarded")
                    completionDelegate?.completionNotifyingDidComplete(self)
                    return UIViewController()
                }
            }
        }

        func updateUIViewController(
            _ uiViewController: UIViewController,
            context _: UIViewControllerRepresentableContext<CGMSetupView>
        ) {
            uiViewController.isModalInPresentation = true
        }
    }
}
