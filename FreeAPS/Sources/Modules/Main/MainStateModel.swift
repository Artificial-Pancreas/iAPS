import LoopKitUI
import SwiftMessages
import SwiftUI
import Swinject

extension Main {
    final class StateModel: BaseStateModel<Provider>, LifetimeOwner {
        @Injected() private var deviceManager: DeviceDataManager!
        @Injected() private var appCoordinator: AppCoordinator!

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
                await me.alertMessageReceived(message)
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

        private func alertMessageReceived(_ message: MessageContent) {
            var config = SwiftMessages.defaultConfig
            let view = MessageView.viewFromNib(layout: .cardView)

            let titleContent: String

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
                view.buttonTapHandler = { _ in
                    SwiftMessages.hide()
                }
            case .errorPump:
                view.configureTheme(.error, iconStyle: .subtle)
                config.duration = .forever
                view.button?.setImage(Icon.errorSubtle.image, for: .normal)
                titleContent = NSLocalizedString("Error", comment: "Error title")
                view.buttonTapHandler = { _ in
                    SwiftMessages.hide()
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

            view.titleLabel?.text = titleContent
            config.dimMode = .gray(interactive: true)

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

extension Main.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        // close the window
        router.mainSecondaryModalView.send(nil)
    }
}
