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
        initial: @escaping @MainActor @Sendable(T) -> Void,
        map: ((T) -> T)? = nil,
        didSet: (@MainActor @Sendable(T) async -> Void)? = nil
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
                    await didSet?(value)
                }
            }
            .store(in: lifetime)
    }

    /// Two-way version of `subscribeSetting`: seeds the model property from the current
    /// settings, saves edits of the property into the settings, and also reflects settings
    /// changes made elsewhere back into the property while the screen is open.
    ///
    /// Both `on:` (the `$property` publisher, to watch local edits) and `at:` (the key path,
    /// to write external changes back) must point at the same property. The write-back is
    /// equality-guarded, so the echo of a local edit does not re-fire `objectWillChange`;
    /// the echo of an external change is a no-op in `updateSettings` (same value).
    func bindSetting<Model: AnyObject & Sendable, T: Equatable & Sendable>(
        _ keyPath: WritableKeyPath<FreeAPSSettings, T> & Sendable,
        on settingPublisher: some Publisher<T, Never>,
        into model: Model,
        at modelKeyPath: ReferenceWritableKeyPath<Model, T>,
        map: ((T) -> T)? = nil,
        didSet: (@MainActor @Sendable(T) async -> Void)? = nil
    ) {
        subscribeSetting(
            keyPath,
            on: settingPublisher,
            initial: { [weak model] in model?[keyPath: modelKeyPath] = $0 },
            map: map,
            didSet: didSet
        )
        // the transform must be explicitly @Sendable: a plain closure literal formed here would be
        // inferred @MainActor (this method is main-isolated) and would trap when the settings
        // subject sends from SettingsManager's executor, before the `receive(on:)` hop below
        let extract: @Sendable(FreeAPSSettings) -> T = { $0[keyPath: keyPath] }
        appCoordinator.settings
            .map(extract)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak model] value in
                MainActor.assumeIsolated {
                    guard let model, model[keyPath: modelKeyPath] != value else { return }
                    model[keyPath: modelKeyPath] = value
                }
            }
            .store(in: lifetime)
    }

    func background(_ operation: @escaping () async -> Void) {
        Task { await operation() }.store(in: lifetime)
    }
}

/// What `@Setting` needs from its enclosing model. `BaseStateModel` conforms below;
/// the wrapper is not usable outside of it.
@MainActor protocol SettingsBindable: AnyObject, ObservableObject {
    var settingsManager: SettingsManager! { get }
    var appCoordinator: AppCoordinator! { get }
}

extension BaseStateModel: SettingsBindable {}

/// A two-way binding between a state-model property and a `FreeAPSSettings` field:
///
///     @Setting(\.allowOneMinuteGlucose) var allowOneMinuteGlucose = false
///
/// Replaces the `@Published var` + `subscribeSetting`/`bindSetting` pair. Reads come from a
/// local cache (so a toggle echoes instantly, without waiting for the settings round-trip);
/// writes update the cache, fire `objectWillChange`, and save into the settings; settings
/// changes made elsewhere are reflected back into the cache while the model is alive.
/// All transitions are equality-guarded, so the echo of a local edit neither re-renders
/// nor re-saves.
///
/// On the first access through the enclosing model the wrapper seeds the cache from the
/// current settings (the declared default only covers the window before that) and
/// subscribes to the settings bus.
@MainActor
@propertyWrapper final class Setting<Value: Equatable & Sendable> {
    private let settingsKeyPath: WritableKeyPath<FreeAPSSettings, Value> & Sendable
    private var cache: Value
    private var subscription: AnyCancellable?

    init(wrappedValue: Value, _ settingsKeyPath: WritableKeyPath<FreeAPSSettings, Value> & Sendable) {
        cache = wrappedValue
        self.settingsKeyPath = settingsKeyPath
    }

    @available(*, unavailable, message: "@Setting can only be used in a BaseStateModel") var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() } // swiftlint:disable:this unused_setter_value
    }

    static subscript<Model: SettingsBindable>(
        _enclosingInstance model: Model,
        wrapped _: ReferenceWritableKeyPath<Model, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<Model, Setting<Value>>
    ) -> Value where Model.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let wrapper = model[keyPath: storageKeyPath]
            wrapper.attachIfNeeded(to: model)
            return wrapper.cache
        }
        set {
            let wrapper = model[keyPath: storageKeyPath]
            wrapper.attachIfNeeded(to: model)
            guard wrapper.cache != newValue else { return }
            model.objectWillChange.send()
            wrapper.cache = newValue
            wrapper.save(newValue, via: model.settingsManager)
        }
    }

    private func attachIfNeeded<Model: SettingsBindable>(
        to model: Model
    ) where Model.ObjectWillChangePublisher == ObservableObjectPublisher {
        guard subscription == nil else { return }
        let keyPath = settingsKeyPath
        let settings = model.appCoordinator.settings
        cache = settings.value[keyPath: keyPath]
        // the transform must be explicitly @Sendable: a plain closure literal formed here would be
        // inferred @MainActor (this method is main-isolated) and would trap when the settings
        // subject sends from SettingsManager's executor, before the `receive(on:)` hop below
        let extract: @Sendable(FreeAPSSettings) -> Value = { $0[keyPath: keyPath] }
        // the model owns the wrapper, so both captures must be weak to avoid a cycle
        subscription = settings
            .map(extract)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak model] value in
                MainActor.assumeIsolated {
                    guard let self, let model, self.cache != value else { return }
                    model.objectWillChange.send()
                    self.cache = value
                }
            }
    }

    private func save(_ value: Value, via settingsManager: SettingsManager) {
        let keyPath = settingsKeyPath
        Task {
            await settingsManager.updateSettings { settings in
                var updated = settings
                updated[keyPath: keyPath] = value
                return updated
            }
        }
    }
}
