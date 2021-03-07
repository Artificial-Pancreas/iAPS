import Combine
import SwiftUI
import Swinject

extension Main {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: MainProvider {
        @Published private(set) var isAuthotized = false
        private(set) var modal: Modal?
        @Published var isModalPresented = false
        @Published private(set) var scene: Scene!
        private var nextModal: Modal?

        required init(provider: Provider, resolver: Resolver) {
            super.init(provider: provider, resolver: resolver)
            scene = isAuthotized ? .authorized : .onboarding
        }

        override func subscribe() {
            router.mainModalScreen
                .map { $0?.modal(resolver: self.resolver) }
                .removeDuplicates { $0?.id == $1?.id }
                .receive(on: RunLoop.main)
                .sink { modal in
                    self.modal = modal
                    self.isModalPresented = modal != nil
                }
                .store(in: &lifetime)

            provider.authorizationManager
                .authorizationPublisher
                .receive(on: RunLoop.main)
                .assign(to: \.isAuthotized, on: self)
                .store(in: &lifetime)

            $isAuthotized
                .sink { isAuthotized in
                    self.scene = isAuthotized ? .authorized : .onboarding
                }
                .store(in: &lifetime)

            $isModalPresented
                .filter { !$0 }
                .sink { _ in
                    self.router.mainModalScreen.send(nil)
                }
                .store(in: &lifetime)
        }
    }
}
