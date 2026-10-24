import LoopKitUI
import SwiftMessages
import SwiftUI
import Swinject
import UIKit

extension Main {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var deviceAlertManager: DeviceAlertManager!

        private var alertCardMenus: [String: DeviceAlertCardMenu] = [:]

        private var alertCardIdentifiers: [AlertIdentity: String] = [:]
        private var alertCardCounter: UInt64 = 0

        private(set) var modal: Modal?
        @Published var isModalPresented = false
        @Published var isSecondaryModalPresented = false
        @Published var secondaryModalView: AnyView? = nil
        @Published var shouldPreventModalDismiss = false

        private let resolver: Resolver

        override init(resolver: Resolver) {
            self.resolver = resolver
            super.init(resolver: resolver)
        }

        override func subscribe() async {
            observe(router.mainModalScreen.removeDuplicates { $0?.id == $1?.id }) { me, screen in
                await me.mainModalScreenUpdated(screen)
            }

            observe($isModalPresented.filter { !$0 }) { me, _ in
                await me.modalDismissed()
            }

            observe(appCoordinator.alertMessages) { me, message in
                switch message {
                case let .show(content): await me.alertMessageReceived(content)
                case let .dismiss(identity): await me.alertDismissed(identity)
                }
            }

            // cannot use `observe` for this one because AnyView is not sendable
            router.mainSecondaryModalView
                .receive(on: DispatchQueue.main)
                .sink { [weak self] view in
                    self?.mainSecondaryModalViewUpdated(view)
                }
                .store(in: lifetime)

            observe($isSecondaryModalPresented.removeDuplicates().filter { !$0 }) { me, _ in
                await me.secondaryModalDismissed()
            }

            appCoordinator.setAlertPresentationReady()
        }

        private func mainModalScreenUpdated(_ screen: Screen?) {
            let modal = screen?.modal(resolver: resolver)
            self.modal = modal
            isModalPresented = modal != nil
        }

        private func mainSecondaryModalViewUpdated(_ view: AnyView?) {
            secondaryModalView = view
            isSecondaryModalPresented = view != nil
        }

        private func acknowledgeAlert(for message: MessageContent) {
            guard let identity = message.alertIdentity else { return }
            if let messageIdentifier = alertCardIdentifiers.removeValue(forKey: identity) {
                alertCardMenus[messageIdentifier] = nil
            }
            deviceAlertManager.alertCardDismissed(identity)
            Task { [deviceManager] in await deviceManager?.acknowledgeDeviceAlert(identity, recordIdentifier: nil) }
        }

        /// The alert is over - retracted by the device, or acknowledged somewhere else
        private func alertDismissed(_ identity: AlertIdentity) {
            guard let messageIdentifier = alertCardIdentifiers.removeValue(forKey: identity) else { return }
            alertCardMenus[messageIdentifier] = nil
            SwiftMessages.hide(id: messageIdentifier)
        }

        private func dismissAllAlerts(from managerIdentifier: String) {
            warning(.deviceManager, "User dismissed all alerts of '\(managerIdentifier)' from the alert card")
            deviceAlertManager.retractAllAlerts(managerIdentifier: managerIdentifier)
        }

        private func deviceName(for managerIdentifier: String) -> String {
            if let pump = appCoordinator.pumpInfo.value, pump.identifier == managerIdentifier {
                return pump.name
            }
            if let cgm = appCoordinator.cgmInfo.value, cgm.identifier == managerIdentifier {
                return cgm.name
            }
            return managerIdentifier
        }

        private func alertMessageReceived(_ message: MessageContent) {
            var config = SwiftMessages.defaultConfig
            let view = MessageView.viewFromNib(layout: .cardView)

            let titleContent: String
            /// What the card's button - and, for a device alert, the card itself - does when tapped.
            var acknowledgeAction: (() -> Void)?

            view.configureContent(
                title: "title",
                body: NSLocalizedString(message.content, comment: "Info message"),
                iconImage: nil,
                iconText: nil,
                buttonImage: nil,
                buttonTitle: nil,
                buttonTapHandler: nil
            )

            switch message.type {
            case .info:
                view.backgroundColor = .secondarySystemGroupedBackground
                config.duration = .automatic

                titleContent = NSLocalizedString("Info", comment: "Info title")
            case .warning:
                view.configureTheme(.warning, iconStyle: .subtle)
                config.duration = .forever
                view.button?.setImage(Icon.warningSubtle.image, for: .normal)
                titleContent = NSLocalizedString("Warning", comment: "Warning title")
                acknowledgeAction = { [weak self] in
                    SwiftMessages.hide()
                    self?.acknowledgeAlert(for: message)
                }
            case .errorPump:
                view.configureTheme(.error, iconStyle: .subtle)
                config.duration = .forever
                view.button?.setImage(Icon.errorSubtle.image, for: .normal)
                titleContent = NSLocalizedString("Error", comment: "Error title")
                acknowledgeAction = { [weak self] in
                    SwiftMessages.hide()
                    guard let self else { return }
                    self.acknowledgeAlert(for: message)
                    // display the pump configuration immediatly
                    if self.appCoordinator.pumpInfo.value != nil
                    {
                        let view = PumpConfig.PumpSettingsView(
                            deviceManager: self.deviceManager,
                            completionDelegate: self
                        ).asAny()
                        self.router.mainSecondaryModalView.send(view)
                    }
                }
            }

            view.buttonTapHandler = acknowledgeAction.map { action in { _ in action() } }

            view.titleLabel?.text = titleContent
            config.dimMode = .gray(interactive: true)
            if let identity = message.alertIdentity {
                if let replaced = alertCardIdentifiers[identity] {
                    alertCardMenus[replaced] = nil
                    SwiftMessages.hide(id: replaced)
                }
                alertCardCounter &+= 1
                let messageIdentifier =
                    "device-alert:\(identity.managerIdentifier).\(identity.alertIdentifier)#\(alertCardCounter)"
                alertCardIdentifiers[identity] = messageIdentifier
                view.id = messageIdentifier
                view.button?.setImage(nil, for: .normal)
                view.button?.setTitle(
                    message.acknowledgeButtonLabel ?? NSLocalizedString("OK", comment: "Acknowledge a device alert"),
                    for: .normal
                )
                view.tapHandler = acknowledgeAction.map { action in { _ in action() } }

                config.dimMode = .gray(interactive: false)
                config.interactiveHide = false

                let menu = DeviceAlertCardMenu(
                    identity: identity,
                    deviceName: deviceName(for: identity.managerIdentifier),
                    dismissAll: { [weak self] managerIdentifier in
                        self?.dismissAllAlerts(from: managerIdentifier)
                    }
                )
                alertCardMenus[messageIdentifier] = menu
                view.addInteraction(UIContextMenuInteraction(delegate: menu))
            }

            SwiftMessages.show(config: config, view: view)
        }

        private func modalDismissed() {
            router.mainModalScreen.send(nil)
        }

        private func secondaryModalDismissed() {
            router.mainSecondaryModalView.send(nil)
        }
    }
}

/// The long-press menu on a device alert's card. The card is SwiftMessages' UIKit `MessageView`, not a
/// SwiftUI view, so this is a `UIContextMenuInteraction` rather than `.contextMenu` - and a context
/// menu rather than an action sheet, which would need a view controller to present from inside
/// SwiftMessages' own window.
@MainActor private final class DeviceAlertCardMenu: NSObject, UIContextMenuInteractionDelegate {
    private let identity: AlertIdentity
    private let deviceName: String
    private let dismissAll: (String) -> Void

    init(identity: AlertIdentity, deviceName: String, dismissAll: @escaping (String) -> Void) {
        self.identity = identity
        self.deviceName = deviceName
        self.dismissAll = dismissAll
    }

    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [identity, deviceName, dismissAll] _ in
            let confirm = UIAction(
                title: NSLocalizedString("Dismiss", comment: "Confirm dismissing all alerts of a device"),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                dismissAll(identity.managerIdentifier)
            }
            // The confirmation step: the destructive action only appears once this is opened.
            let confirmation = UIMenu(
                title: NSLocalizedString(
                    "Dismiss all alerts from this device?",
                    comment: "Confirmation for dismissing all alerts of a device"
                ),
                options: .destructive,
                children: [confirm]
            )
            return UIMenu(
                title: String(
                    format: NSLocalizedString(
                        "Dismiss all alerts from %@",
                        comment: "Long-press menu on a device alert card"
                    ),
                    deviceName
                ),
                subtitle: NSLocalizedString(
                    "Clears these alerts on the phone only. The device is not told, and may keep alarming until it is reset or reconnected.",
                    comment: "Explanation of dismissing all alerts of a device"
                ),
                children: [confirmation]
            )
        }
    }
}

extension Main.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        // close the window
        router.mainSecondaryModalView.send(nil)
    }
}
