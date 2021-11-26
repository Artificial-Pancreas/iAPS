import UIKit
import SwiftUI
import HealthKit

public struct LibreTransmitterSetupView: UIViewControllerRepresentable {
    public class Coordinator: CompletionDelegate, CGMManagerSetupViewControllerDelegate {
        let completion: (() -> Void)?
        let setup: ((LibreTransmitterManager) -> Void)?

        public func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: LibreTransmitterManager) {
            setup?(cgmManager)
        }

        public func completionNotifyingDidComplete(_ object: CompletionNotifying) {
            completion?()
        }

        init(completion: (() -> Void)?, setup: ((LibreTransmitterManager) -> Void)?) {
            self.completion = completion
            self.setup = setup
        }
    }

    private let setup: ((LibreTransmitterManager) -> Void)?
    private let completion: (() -> Void)?

    public init(setup: ((LibreTransmitterManager) -> Void)? = nil , completion: (() -> Void)? = nil) {
        self.setup = setup
        self.completion = completion
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        let controller = LibreTransmitterSetupViewController()
        controller.completionDelegate = context.coordinator
        controller.setupDelegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion, setup: setup)
    }
}

public struct LibreTransmitterSettingsView: UIViewControllerRepresentable {
    public class Coordinator: CompletionDelegate {
        let completion: (() -> Void)?
        let delete: (() -> Void)?

        public func completionNotifyingDidComplete(_ object: CompletionNotifying) {
            completion?()
        }

        init(completion: (() -> Void)?, delete: (() -> Void)?) {
            self.completion = completion
            self.delete = delete
        }
    }

    private weak var manager: LibreTransmitterManager!
    private let glucoseUnit: HKUnit
    private let delete: (() -> Void)?
    private let completion: (() -> Void)?

    public init(manager: LibreTransmitterManager, glucoseUnit: HKUnit, delete: (() -> Void)? = nil , completion: (() -> Void)? = nil) {
        self.manager = manager
        self.glucoseUnit = glucoseUnit
        self.delete = delete
        self.completion = completion
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        let doneNotifier = GenericObservableObject()
        let wantToTerminateNotifier = GenericObservableObject()

        let settings = SettingsView.asHostedViewController(
            glucoseUnit: glucoseUnit,
            //displayGlucoseUnitObservable: displayGlucoseUnitObservable,
            notifyComplete: doneNotifier,
            notifyDelete: wantToTerminateNotifier,
            transmitterInfoObservable: manager.transmitterInfoObservable,
            sensorInfoObervable: manager.sensorInfoObservable,
            glucoseInfoObservable: manager.glucoseInfoObservable
        )

        let nav = SettingsNavigationViewController(rootViewController: settings)
        nav.navigationItem.title = NSLocalizedString("Libre Bluetooth", comment: "Libre Bluetooth")
        nav.completionDelegate = context.coordinator

        doneNotifier.listenOnce { [weak nav] in
            nav?.notifyComplete()
        }

        wantToTerminateNotifier.listenOnce { [weak nav] in
            manager.logger.debug("CGM wants to terminate")
            manager.disconnect()
            UserDefaults.standard.preSelectedDevice = nil
            context.coordinator.delete?()
            nav?.notifyComplete()
        }

        return nav
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion, delete: delete)
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
