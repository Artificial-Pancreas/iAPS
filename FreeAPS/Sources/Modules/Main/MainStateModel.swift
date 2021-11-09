import SwiftUI
import Swinject

extension Main {
    final class StateModel: BaseStateModel<Provider> {
        private(set) var modal: Modal?
        @Published var isModalPresented = false
        @Published var isAlertPresented = false
        @Published var alertMessage = ""

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
                    self.isAlertPresented = true
                    self.alertMessage = message
                }
                .store(in: &lifetime)
        }
    }
}
