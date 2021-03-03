import Combine
import Foundation
import Swinject

protocol NetworkManager {
    func fetchGlucose() -> AnyPublisher<[BloodGlucose], Error>
}

final class BaseNetworkManager: NetworkManager, Injectable {
    @Injected() private var keychain: Keychain!

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func fetchGlucose() -> AnyPublisher<[BloodGlucose], Error> {
        guard let nightscout = nightscoutAPI else {
            return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
        }
        return nightscout.fetchLast(288)
    }
}
