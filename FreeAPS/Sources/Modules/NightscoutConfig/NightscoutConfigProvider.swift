import Combine
import Foundation

extension NightscoutConfig {
    final class Provider: BaseProvider, NightscoutConfigProvider {
        func checkConnection(url: URL, secret: String?) -> AnyPublisher<Void, Error> {
            NightscoutAPI(url: url, secret: secret).checkConnection()
        }
    }
}
