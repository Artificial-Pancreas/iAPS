import SwiftUI

extension Sharing {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var userToken: UserToken!

        @Published var uploadStats: Bool = false
        @Published var uploadLogs: Bool = false
        @Published var uploadCrashReports: Bool = false
        @Published var identifier: String = ""
        // The values are set in Settings › Demographics (pushed from here too): read here, and followed while shown.
        @Setting(\.sexSetting) var sexSetting: Int = 3
        @Setting(\.birthDate) var birthDate = Date.distantPast
        // Whether the daily statistics carry them.
        @Setting(\.shareSex) var shareSex: Bool = false
        @Setting(\.shareAge) var shareAge: Bool = false

        override func subscribe() async {
            subscribeSetting(\.uploadStats, on: $uploadStats) { self.uploadStats = $0 }
            subscribeSetting(\.uploadLogs, on: $uploadLogs) { self.uploadLogs = $0 }
            subscribeSetting(\.uploadCrashReports, on: $uploadCrashReports) { self.uploadCrashReports = $0 }

            identifier = userToken.getIdentifier()
        }

        var demographics: DemographicsSharing {
            DemographicsSharing(sexSetting: sexSetting, birthDate: birthDate, shareSex: shareSex, shareAge: shareAge)
        }

        /// Logs require two anonymous demographics, shared: a usable hormonal sex signal
        /// (Woman/Man) and a plausible age. Anything else can't anchor the stats.
        var demographicsQualifyForLogs: Bool {
            demographics.qualifiesForLogs(now: Date(), calendar: .current)
        }
    }
}
