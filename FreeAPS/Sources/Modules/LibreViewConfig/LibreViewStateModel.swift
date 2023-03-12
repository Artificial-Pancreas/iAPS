import Combine
import SwiftDate
import SwiftUI

extension LibreViewConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var keychain: Keychain!
        @Injected() private var libreLinkManager: LibreLinkManager!

        @Published var login = ""
        @Published var password = ""
        @Published var token = ""
        @Published var server = 0
        @Published var customServer = ""
        @Published var allowUploadGlucose = false

        @Published var alertMessage: String?
        @Published var lastUpload = 0.0
        @Published var uploadsFrequency = 0
        @Published var nextUploadDelta = 0.0

        @Published var onLoading = false
        @Published var onUploading = false

        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter
        }()

        override func subscribe() {
            login = keychain.getValue(String.self, forKey: Config.lvLoginKey) ?? ""
            password = keychain.getValue(String.self, forKey: Config.lvPasswordKey) ?? ""
            token = keychain.getValue(String.self, forKey: Config.lvTokenKey) ?? ""

            $login.sink { [weak self] login in
                self?.keychain.setValue(login, forKey: Config.lvLoginKey)
            }.store(in: &lifetime)

            $password.sink { [weak self] password in
                self?.keychain.setValue(password, forKey: Config.lvPasswordKey)
            }.store(in: &lifetime)

            $token.sink { [weak self] token in
                self?.keychain.setValue(token, forKey: Config.lvTokenKey)
            }.store(in: &lifetime)

            subscribeSetting(\.libreViewServer, on: $server) { server = $0 }
            subscribeSetting(\.libreViewCustomServer, on: $customServer) { customServer = $0 }
            subscribeSetting(\.libreViewLastUploadTimestamp, on: $lastUpload) { lastUpload = $0 }
            subscribeSetting(\.libreViewLastAllowUploadGlucose, on: $allowUploadGlucose) { allowUploadGlucose = $0 }
            subscribeSetting(\.libreViewFrequenceUploads, on: $uploadsFrequency) { uploadsFrequency = $0 }
            subscribeSetting(\.libreViewNextUploadDelta, on: $nextUploadDelta) { nextUploadDelta = $0 }
        }

        func connect() {
            guard let server = Server.byViewTag(server),
                  let url = server == .custom ? URL(string: customServer) : URL(string: "https://\(server.rawValue)")
            else {
                alertMessage = "Please, set correct LibreView server"
                return
            }
            onLoading = true
            provider.createConnection(url: url, username: login, password: password)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    switch completion {
                    case .finished: break
                    case let .failure(error):
                        self?.alertMessage = error.localizedDescription
                        self?.token = ""
                    }
                    self?.onLoading = false
                } receiveValue: { response in
                    self.token = response
                }
                .store(in: &lifetime)
        }

        func forceUploadGlocose() {
            guard let server = Server.byViewTag(server),
                  let url = server == .custom ? URL(string: customServer) : URL(string: "https://\(server.rawValue)")
            else {
                alertMessage = "Please, set correct LibreView server"
                return
            }
            let currentTimestamp = Date().timeIntervalSince1970
            onUploading = true
            libreLinkManager
                .uploadGlucose(
                    url: url,
                    token: token,
                    from: lastUpload,
                    to: currentTimestamp
                )
                .receive(on: DispatchQueue.main)
                .sink { [weak self] completion in
                    switch completion {
                    case .finished: break
                    case let .failure(error):
                        self?.alertMessage = error.localizedDescription
                        debug(.librelink, "Error during uploading data: \(error.localizedDescription)")
                    }
                    self?.onUploading = false
                } receiveValue: { _ in
                    self.alertMessage = "Glucose was upload success"
                    self.onUploading = false
                    self.lastUpload = currentTimestamp
                }
                .store(in: &lifetime)
        }

        func updateUploadTimestampDelta() {
            guard let frequency = LibreViewConfig.UploadsFrequency(rawValue: uploadsFrequency)
            else {
                uploadsFrequency = 0
                nextUploadDelta = 0
                return
            }
            nextUploadDelta = frequency.secondsToNextUpload
        }
    }
}
