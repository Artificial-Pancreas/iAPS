import SwiftUI

extension Sharing {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var userToken: Token!

        @Published var uploadStats: Bool = false
        @Published var uploadLogs: Bool = false
        @Published var identifier: String = ""
        @Published var birthDate = Date.distantPast
        @Published var sexSetting: Int = 0
        @Published var sex: Sex = .woman

        override func subscribe() async {
            subscribeSetting(\.uploadStats, on: $uploadStats) { self.uploadStats = $0 }
            subscribeSetting(\.uploadLogs, on: $uploadLogs) { self.uploadLogs = $0 }
            subscribeSetting(\.birthDate, on: $birthDate) { self.birthDate = $0 }
            subscribeSetting(\.sexSetting, on: $sexSetting) { self.sexSetting = $0 }

            sex = Sex.savedSettings(sexSetting)

            identifier = userToken.getIdentifier()
        }
    }
}
