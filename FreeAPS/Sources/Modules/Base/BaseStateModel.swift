import Combine
import SwiftUI
import Swinject

protocol StateModel: ObservableObject {
    var resolver: Resolver { get }
//    var isInitial: Bool { get set }
    func subscribe()
    func showModal(for screen: Screen?)
    func hideModal()
    func view(for screen: Screen) -> AnyView
}

class BaseStateModel<Provider>: StateModel, Injectable where Provider: FreeAPS.Provider {
    let router: Router
    let settingsManager: SettingsManager!

//    var isInitial: Bool = true

    let provider: Provider

    let resolver: Resolver

    init(resolver: Resolver) {
        self.resolver = resolver
        router = resolver.resolve(Router.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        provider = Provider(resolver: resolver)
        injectServices(resolver)
//        self.isInitial = false
        subscribe()
    }

    var lifetime = Lifetime()

    func subscribe() {}

    func showModal(for screen: Screen?) {
        router.mainModalScreen.send(screen)
    }

    func hideModal() {
        router.mainModalScreen.send(nil)
    }

    func view(for screen: Screen) -> AnyView {
        router.view(for: screen)
    }

    func subscribeSetting<T: Equatable, U: Publisher>(
        _ keyPath: WritableKeyPath<FreeAPSSettings, T>,
        on settingPublisher: U, initial: (T) -> Void, map: ((T) -> (T))? = nil, didSet: ((T) -> Void)? = nil
    ) where U.Output == T, U.Failure == Never {
        initial(settingsManager.settings[keyPath: keyPath])
        settingPublisher
            .removeDuplicates()
            .map(map ?? { $0 })
            .sink { [weak self] value in
                self?.settingsManager.settings[keyPath: keyPath] = value
                didSet?(value)
            }
            .store(in: &lifetime)
    }
}
