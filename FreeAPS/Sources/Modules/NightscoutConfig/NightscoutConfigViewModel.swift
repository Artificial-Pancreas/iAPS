import SwiftUI

extension NightscoutConfig {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: NightscoutConfigProvider {
        @Injected() var keychain: Keychain!

        @Published var url = ""
        @Published var secret = ""

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
        }

        func connect() {
            // TODO: check connection
            keychain.setValue(url, forKey: Config.urlKey)
            keychain.setValue(url, forKey: Config.secretKey)
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
        }
    }
}
