import Foundation

/// builds the NightscoutAPI client it from the keychain configuration
/// rebuilds it when the configuration changes.
final class NightscoutAPIProvider: LifetimeOwner, AppServiceSync, @unchecked Sendable {
    private let keychain: Keychain
    private let appCoordinator: AppCoordinator

    let lifetime = Lifetime()

    @Protected private var current: NightscoutAPI? = nil

    var api: NightscoutAPI? { current }

    init(keychain: Keychain, appCoordinator: AppCoordinator) {
        self.keychain = keychain
        self.appCoordinator = appCoordinator
    }

    func start() {
        reload()

        observe(appCoordinator.nightscoutConfigChanged) { me, _ in
            me.reload()
        }
    }

    private func reload() {
        current = makeNightscoutAPI()
    }

    private func makeNightscoutAPI() -> NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }
}
