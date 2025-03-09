import SwiftUI

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var nightscoutManager: NightscoutManager!

        @Published var closedLoop = false
        @Published var debugOptions = false
        @Published var animatedBackground = false
        @Published var disableCGMError = true
        @Published var profileID: String = "Hypo Treatment"
        @Published var allowDilution = false
        @Published var extended_overrides = false

        private(set) var buildNumber = ""
        private(set) var versionNumber = ""
        private(set) var branch = ""
        private(set) var copyrightNotice = ""

        override func subscribe() {
            nightscoutManager.fetchVersion()
            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.closedLoop, on: $closedLoop) { closedLoop = $0 }
            subscribeSetting(\.disableCGMError, on: $disableCGMError) { disableCGMError = $0 }
            subscribeSetting(\.profileID, on: $profileID) { profileID = $0 }
            subscribeSetting(\.allowDilution, on: $allowDilution) { allowDilution = $0 }
            subscribeSetting(\.extended_overrides, on: $extended_overrides) { extended_overrides = $0 }

            broadcaster.register(SettingsObserver.self, observer: self)
            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
            versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            // Read branch information from the branch.txt instead of infoDictionary
            if let branchFileURL = Bundle.main.url(forResource: "branch", withExtension: "txt"),
               let branchFileContent = try? String(contentsOf: branchFileURL)
            {
                let lines = branchFileContent.components(separatedBy: .newlines)
                for line in lines {
                    let components = line.components(separatedBy: "=")
                    if components.count == 2 {
                        let key = components[0].trimmingCharacters(in: .whitespaces)
                        let value = components[1].trimmingCharacters(in: .whitespaces)

                        if key == "BRANCH" {
                            branch = value
                            break
                        }
                    }
                }
            } else {
                branch = "Unknown"
            }

            copyrightNotice = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

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

        func uploadProfileAndSettings(_ force: Bool) {
            NSLog("SettingsState Upload Profile and Settings")
            nightscoutManager.uploadProfileAndSettings(force)
        }

        func hideSettingsModal() {
            hideModal()
        }

        func deleteOverrides() {
            nightscoutManager.deleteAllNSoverrrides() // For testing
        }
    }
}

extension Settings.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: FreeAPSSettings) {
        closedLoop = settings.closedLoop
        debugOptions = settings.debugOptions
        disableCGMError = settings.disableCGMError
        allowDilution = settings.allowDilution
    }
}
