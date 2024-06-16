import SwiftUI

extension Sharing {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() private var keychain: Keychain!

        @Published var uploadStats: Bool = false
        @Published var identfier: String = ""
        @Published var birthDate = Date.distantPast
        @Published var uploadVersion: Bool = true
        @Published var sexSetting: Int = 3
        @Published var sex: Sex = .secret

        override func subscribe() {
            uploadStats = settingsManager.settings.uploadStats
            subscribeSetting(\.uploadStats, on: $uploadStats) { uploadStats = $0 }
            subscribeSetting(\.uploadVersion, on: $uploadVersion) { uploadVersion = $0 }
            subscribeSetting(\.birthDate, on: $birthDate) { birthDate = $0 }
            subscribeSetting(\.sexSetting, on: $sexSetting) { sexSetting = $0 }
            identfier = getIdentifier()
        }

        private func getIdentifier() -> String {
            var identfier = keychain.getValue(String.self, forKey: IAPSconfig.id) ?? ""
            guard identfier.count > 1 else {
                identfier = UUID().uuidString
                keychain.setValue(identfier, forKey: IAPSconfig.id)
                return identfier
            }
            return identfier
        }

        func savedSettings() {
            switch sexSetting {
            case 0:
                sex = .woman
            case 1:
                sex = .man
            case 2:
                sex = .other
            default:
                sex = .secret
            }
        }

        func saveSetting() {
            switch sex {
            case .woman:
                sexSetting = 0
            case .man:
                sexSetting = 1
            case .other:
                sexSetting = 2
            case .secret:
                sexSetting = 3
            }
        }
    }
}
