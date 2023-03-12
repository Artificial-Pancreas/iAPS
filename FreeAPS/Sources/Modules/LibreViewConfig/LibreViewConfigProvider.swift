import Combine
import Foundation

extension LibreViewConfig {
    final class Provider: BaseProvider, LibreViewConfigProvider {
        @Injected() private var libreViewManager: LibreLinkManager!

        func createConnection(url: URL, username: String, password: String) -> AnyPublisher<LibreLinkToken, Error> {
            libreViewManager.createConnection(url: url, username: username, password: password)
        }
    }
}
