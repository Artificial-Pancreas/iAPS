import SwiftMessages
import SwiftUI
import Swinject

extension Main {
    final class StateModel: BaseStateModel<Provider> {
        private(set) var modal: Modal?
        @Published var isModalPresented = false
        @Published var isSecondaryModalPresented = false
        @Published var secondaryModalView: AnyView? = nil

        override func subscribe() {
            router.mainModalScreen
                .map { $0?.modal(resolver: self.resolver!) }
                .removeDuplicates { $0?.id == $1?.id }
                .receive(on: DispatchQueue.main)
                .sink { modal in
                    self.modal = modal
                    self.isModalPresented = modal != nil
                }
                .store(in: &lifetime)

            $isModalPresented
                .filter { !$0 }
                .sink { _ in
                    self.router.mainModalScreen.send(nil)
                }
                .store(in: &lifetime)

            router.alertMessage
                .receive(on: DispatchQueue.main)
                .sink { message in
                    SwiftMessages.show {
                        let view = MessageView.viewFromNib(layout: .messageView)
                        view.backgroundColor = .secondarySystemGroupedBackground
                        view.titleLabel?.textColor = .label
                        view.bodyLabel?.textColor = .label
                        view.configureContent(
                            title: NSLocalizedString("Info", comment: "Info title"),
                            body: NSLocalizedString(message, comment: "Info message"),
                            iconImage: nil,
                            iconText: nil,
                            buttonImage: nil,
                            buttonTitle: nil,
                            buttonTapHandler: nil
                        )

                        view.bodyLabel?.text = message
                        return view
                    }
                }
                .store(in: &lifetime)

            router.mainSecondaryModalView
                .receive(on: DispatchQueue.main)
                .sink { view in
                    self.secondaryModalView = view
                    self.isSecondaryModalPresented = view != nil
                }
                .store(in: &lifetime)

            $isSecondaryModalPresented
                .removeDuplicates()
                .filter { !$0 }
                .sink { _ in
                    self.router.mainSecondaryModalView.send(nil)
                }
                .store(in: &lifetime)
        }
    }
}
