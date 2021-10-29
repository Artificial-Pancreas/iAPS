import Combine
import SwiftUI
import Swinject

protocol ViewModel {
    func subscribe()
    func view(for screen: Screen) -> AnyView
    func cachedView(for screen: Screen) -> AnyView
    func showModal(for screen: Screen?)
    func hideModal()
    func cleanViewCache()
}

class BaseViewModel<Provider>: ViewModel, Injectable where Provider: FreeAPS.Provider {
    let resolver: Resolver
    let provider: Provider
    var lifetime = Lifetime()
    @Injected() var router: Router!

    private var viewCache: [Screen: AnyView] = [:]

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

    func cachedView(for screen: Screen) -> AnyView {
        if let view = viewCache[screen] {
            return view
        }

        let view = view(for: screen)
        viewCache[screen] = view
        return view
    }

    func cleanViewCache() {
        viewCache.removeAll()
    }

    func showModal(for screen: Screen?) {
        router.mainModalScreen.send(screen)
    }

    func hideModal() {
        router.mainModalScreen.send(nil)
    }
}
