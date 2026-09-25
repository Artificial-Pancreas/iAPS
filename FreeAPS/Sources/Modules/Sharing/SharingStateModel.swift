import SwiftUI

extension Sharing {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() private var keychain: Keychain!

        @Published var uploadStats: Bool = false
        @Published var uploadLogs: Bool = false
        @Published var identfier: String = ""
        @Published var birthDate = Date.distantPast
        @Published var sexSetting: Int = 3
        @Published var sex: Sex = .secret
        // Weight stored canonically in kg, height in cm (0 = unset).
        @Published var weight: Decimal = 0
        @Published var height: Decimal = 0
        @Published var weightInLb: Bool = false
        @Published var heightInFtIn: Bool = false

        override func subscribe() {
            uploadStats = settingsManager.settings.uploadStats
            subscribeSetting(\.uploadStats, on: $uploadStats) { uploadStats = $0 }
            uploadLogs = settingsManager.settings.uploadLogs
            subscribeSetting(\.uploadLogs, on: $uploadLogs) { uploadLogs = $0 }
            subscribeSetting(\.birthDate, on: $birthDate) { birthDate = $0 }
            subscribeSetting(\.sexSetting, on: $sexSetting) { sexSetting = $0 }
            subscribeSetting(\.weight, on: $weight) { weight = $0 }
            subscribeSetting(\.height, on: $height) { height = $0 }
            subscribeSetting(\.weightInLb, on: $weightInLb) { weightInLb = $0 }
            subscribeSetting(\.heightInFtIn, on: $heightInFtIn) { heightInFtIn = $0 }
            identfier = getIdentifier()
        }

        /// Logs require two anonymous demographics: a usable hormonal sex signal
        /// (Woman/Man) and a plausible age. Anything else can't anchor the stats.
        var demographicsQualifyForLogs: Bool {
            guard sex.hasHormonalSignal else { return false }
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? -1
            return age >= 1 && age <= 120
        }

        private func getIdentifier() -> String {
            keychain.getIdentifier()
        }
    }
}

extension Keychain {
    func getIdentifier() -> String {
        var identfier = getValue(String.self, forKey: IAPSconfig.id) ?? ""
        guard identfier.count > 1 else {
            identfier = UUID().uuidString
            setValue(identfier, forKey: IAPSconfig.id)
            return identfier
        }
        return identfier
    }
}
