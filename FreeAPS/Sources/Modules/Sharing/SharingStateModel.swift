import SwiftUI

extension Sharing {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var userToken: UserToken!

        @Published var uploadStats: Bool = false
        @Published var uploadLogs: Bool = false
        @Published var identifier: String = ""
        @Published var birthDate = Date.distantPast
        @Published var sexSetting: Int = 3
        @Published var sex: Sex = .secret
        // Weight stored canonically in kg, height in cm (0 = unset).
        @Published var weight: Decimal = 0
        @Published var height: Decimal = 0
        @Published var weightInLb: Bool = false
        @Published var heightInFtIn: Bool = false

        override func subscribe() async {
            subscribeSetting(\.uploadStats, on: $uploadStats) { self.uploadStats = $0 }
            subscribeSetting(\.uploadLogs, on: $uploadLogs) { self.uploadLogs = $0 }
            subscribeSetting(\.birthDate, on: $birthDate) { self.birthDate = $0 }
            subscribeSetting(\.sexSetting, on: $sexSetting) {
                self.sexSetting = $0
                self.sex = Sex.savedSettings($0)
            }
            subscribeSetting(\.weight, on: $weight) { self.weight = $0 }
            subscribeSetting(\.height, on: $height) { self.height = $0 }
            subscribeSetting(\.weightInLb, on: $weightInLb) { self.weightInLb = $0 }
            subscribeSetting(\.heightInFtIn, on: $heightInFtIn) { self.heightInFtIn = $0 }

            identifier = userToken.getIdentifier()
        }

        /// Logs require two anonymous demographics: a usable hormonal sex signal
        /// (Woman/Man) and a plausible age. Anything else can't anchor the stats.
        var demographicsQualifyForLogs: Bool {
            guard sex.hasHormonalSignal else { return false }
            let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? -1
            return age >= 1 && age <= 120
        }
    }
}
