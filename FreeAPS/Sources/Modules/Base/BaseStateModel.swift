import Combine
import SwiftUI
import Swinject

@MainActor protocol StateModel: ObservableObject {
    func showModal(for screen: Screen?)
    func hideModal()
    func view(for screen: Screen) -> AnyView
}

@MainActor
class BaseStateModel<Provider>: StateModel, Injectable where Provider: FreeAPS.Provider {
    let router: Router
    let settingsManager: SettingsManager!

    //    var isInitial: Bool = true

    let provider: Provider

    private let resolver: Resolver

    var lifetime = Lifetime()

    init(resolver: Resolver) {
        self.resolver = resolver
        router = resolver.resolve(Router.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        provider = Provider(resolver: resolver)
        injectServices(resolver)
//        self.isInitial = false
        Task {
            await subscribe()
        }.store(in: &lifetime)
    }

    func subscribe() async {}

    func showModal(for screen: Screen?) {
        router.mainModalScreen.send(screen)
    }

    func hideModal() {
        router.mainModalScreen.send(nil)
    }

    func view(for screen: Screen) -> AnyView {
        router.view(for: screen)
    }

    func subscribeSetting<T: Equatable>(
        _ keyPath: WritableKeyPath<FreeAPSSettings, T>,
        on settingPublisher: some Publisher<T, Never>,
        initial: @escaping @MainActor(T) -> Void,
        map: ((T) -> T)? = nil,
        didSet: (@MainActor(T) -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else { return }
            initial(await self.settingsManager.settings[keyPath: keyPath])
        }
        settingPublisher
            .removeDuplicates()
            .dropFirst()
            .map(map ?? { $0 })
            .sink { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var settings = await self.settingsManager.settings
                    settings[keyPath: keyPath] = value
                    await self.settingsManager.updateSettings(settings)
                    didSet?(value)
                }
            }
            .store(in: &lifetime)
    }

    func background(_ operation: @escaping () async -> Void) {
        Task { await operation() }.store(in: &lifetime)
    }

    func observe<P: Publisher>(
        _ publisher: P,
        action: @escaping @Sendable(P.Output) async -> Void
    ) where P.Output: Sendable, P.Failure == Never {
        FreeAPS.observe(publisher, in: &lifetime, action: action)
    }
}
