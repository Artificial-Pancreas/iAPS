import SwiftUI

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var nightscoutManager: NightscoutManager!

        @Published var closedLoop = false
        @Published var debugOptions = false
        @Published var animatedBackground = false

        private(set) var buildNumber = ""

        override func subscribe() {
            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.closedLoop, on: $closedLoop) { closedLoop = $0 }

            broadcaster.register(SettingsObserver.self, observer: self)

            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

            subscribeSetting(\.animatedBackground, on: $animatedBackground) { animatedBackground = $0 }
        }

        func logItems() -> [URL] {
            var items: [URL] = []

            if fileManager.fileExists(atPath: SimpleLogReporter.logFile) {
                items.append(URL(fileURLWithPath: SimpleLogReporter.logFile))
            }

            if fileManager.fileExists(atPath: SimpleLogReporter.logFilePrev) {
                items.append(URL(fileURLWithPath: SimpleLogReporter.logFilePrev))
            }

            return items
        }

        func uploadProfile() {
            NSLog("SettingsState Upload Profile")
            nightscoutManager.uploadProfile()
        }

        func hideSettingsModal() {
            nightscoutManager.uploadProfile()
            hideModal()
        }
    }
}

extension Settings.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: FreeAPSSettings) {
        closedLoop = settings.closedLoop
        debugOptions = settings.debugOptions
    }
}
