import Combine
import SwiftUI
import Swinject

protocol ViewModel {
    func subscribe()
    func view(for screen: Screen) -> AnyView
    func showModal(for screen: Screen?)
    func hideModal()
}

class BaseViewModel<Provider>: ViewModel, Injectable where Provider: FreeAPS.Provider {
    let resolver: Resolver
    let provider: Provider
    var lifetime = Lifetime()
    @Injected() var router: Router!

    required init(provider: Provider, resolver: Resolver) {
        self.provider = provider
        self.resolver = resolver
        injectServices(resolver)
        subscribe()
    }

    func subscribe() {}

    func view(for screen: Screen) -> AnyView {
        router.view(for: screen)
    }

    func showModal(for screen: Screen?) {
        router.mainModalScreen.send(screen)
    }

    func hideModal() {
        router.mainModalScreen.send(nil)
    }
}
