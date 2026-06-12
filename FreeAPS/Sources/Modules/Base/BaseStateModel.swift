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
    let appCoordinator: AppCoordinator!

    let provider: Provider

    private let resolver: Resolver

    let lifetime = Lifetime()

    init(resolver: Resolver) {
        self.resolver = resolver
        router = resolver.resolve(Router.self)!
        settingsManager = resolver.resolve(SettingsManager.self)!
        appCoordinator = resolver.resolve(AppCoordinator.self)!
        provider = Provider(resolver: resolver)
        injectServices(resolver)
        Task {
            await subscribe()
        }.store(in: lifetime)
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
        _ keyPath: WritableKeyPath<FreeAPSSettings, T> & Sendable,
        on settingPublisher: some Publisher<T, Never>,
        initial: @escaping @MainActor(T) -> Void,
        map: ((T) -> T)? = nil,
        didSet: (@MainActor(T) -> Void)? = nil
    ) where T: Sendable {
        initial(appCoordinator.settings.value[keyPath: keyPath])
        settingPublisher
            .removeDuplicates()
            .dropFirst()
            .map(map ?? { $0 })
            .sink { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.settingsManager.updateSettings { currentSettings in
                        var updatedSettings = currentSettings
                        updatedSettings[keyPath: keyPath] = value
                        return updatedSettings
                    }
                    didSet?(value)
                }
            }
            .store(in: lifetime)
    }

    func background(_ operation: @escaping () async -> Void) {
        Task { await operation() }.store(in: lifetime)
    }
}
