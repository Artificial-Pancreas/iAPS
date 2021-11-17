import Combine
import SwiftUI

extension NightscoutConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var keychain: Keychain!
        @Injected() var settingsManager: SettingsManager!

        @Published var url = ""
        @Published var secret = ""
        @Published var message = ""
        @Published var connecting = false
        @Published var isUploadEnabled = false

        @Published var useLocalSource = false
        @Published var localPort: Decimal = 0

        override func subscribe() {
            url = keychain.getValue(String.self, forKey: Config.urlKey) ?? ""
            secret = keychain.getValue(String.self, forKey: Config.secretKey) ?? ""
            isUploadEnabled = settingsManager.settings.isUploadEnabled
            useLocalSource = settingsManager.settings.useLocalGlucoseSource
            localPort = Decimal(settingsManager.settings.localGlucosePort)

            $isUploadEnabled
                .removeDuplicates()
                .sink { [weak self] enabled in
                    self?.settingsManager.settings.isUploadEnabled = enabled
                }.store(in: &lifetime)

            $useLocalSource
                .removeDuplicates()
                .sink { [weak self] use in
                    self?.settingsManager.settings.useLocalGlucoseSource = use
                }.store(in: &lifetime)

            $localPort
                .removeDuplicates()
                .sink { [weak self] port in
                    self?.settingsManager.settings.localGlucosePort = Int(port)
                }.store(in: &lifetime)
        }

        func connect() {
            guard let url = URL(string: url) else {
                message = "Invalid URL"
                return
            }
            connecting = true
            message = ""
            provider.checkConnection(url: url, secret: secret.isEmpty ? nil : secret)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished: break
                    case let .failure(error):
                        self.message = "Error: \(error.localizedDescription)"
                    }
                    self.connecting = false
                } receiveValue: {
                    self.message = "Connected!"
                    self.keychain.setValue(self.url, forKey: Config.urlKey)
                    self.keychain.setValue(self.secret, forKey: Config.secretKey)
                }
                .store(in: &lifetime)
        }

        func delete() {
            keychain.removeObject(forKey: Config.urlKey)
            keychain.removeObject(forKey: Config.secretKey)
            url = ""
            secret = ""
        }
    }
}
