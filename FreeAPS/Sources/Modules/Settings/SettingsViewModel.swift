import SwiftUI

extension Settings {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: SettingsProvider {
        @Injected() private var settingsManager: SettingsManager!
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var authorizationManager: AuthorizationManager!
        @Published var closedLoop = false

        @Published var debugOptions = false

        private(set) var buildNumber = ""

        override func subscribe() {
            closedLoop = settingsManager.settings.closedLoop
            debugOptions = settingsManager.settings.debugOptions ?? false

            $closedLoop
                .removeDuplicates()
                .sink { [weak self] value in
                    self?.settingsManager.settings.closedLoop = value
                }.store(in: &lifetime)

            broadcaster.register(SettingsObserver.self, observer: self)

            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
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

        func logout() {
            authorizationManager.logout()
            showModal(for: nil)
        }
    }
}

extension Settings.ViewModel: SettingsObserver {
    func settingsDidChange(_ settings: FreeAPSSettings) {
        closedLoop = settings.closedLoop
        debugOptions = settings.debugOptions ?? false
    }
}
