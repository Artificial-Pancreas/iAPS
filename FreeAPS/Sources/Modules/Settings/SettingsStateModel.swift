import CoreData
import SwiftUI

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var nightscoutManager: NightscoutManager!

        @Published var closedLoop = false
        @Published var debugOptions = false
        @Published var animatedBackground = false
        @Published var profileID: String = "Hypo Treatment"
        @Published var allowDilution = false
        @Published var extended_overrides = false
        @Published var noCarbs = false
        @Published var allowOneMinuteLoop = false
        @Published var allowOneMinuteGlucose = false
        @Published var entities: [Cleared] = CoreDataStack.shared.persistentContainer.managedObjectModel.entities
            .compactMap(\.name).map {
                Cleared(entity: $0, deleted: false)
            }

        private(set) var buildNumber = ""
        private(set) var versionNumber = ""
        private(set) var branch = ""
        private(set) var copyrightNotice = ""

        override func subscribe() {
            nightscoutManager.fetchVersion()
            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.closedLoop, on: $closedLoop) { closedLoop = $0 }
            subscribeSetting(\.profileID, on: $profileID) { profileID = $0 }
            subscribeSetting(\.allowDilution, on: $allowDilution) { allowDilution = $0 }
            subscribeSetting(\.extended_overrides, on: $extended_overrides) { extended_overrides = $0 }
            subscribeSetting(\.noCarbs, on: $noCarbs) { noCarbs = $0 }
            subscribeSetting(\.allowOneMinuteLoop, on: $allowOneMinuteLoop) { allowOneMinuteLoop = $0 }
            subscribeSetting(\.allowOneMinuteGlucose, on: $allowOneMinuteGlucose) { allowOneMinuteGlucose = $0 }

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

            if let zipURL = createZipFile(items: items) {
                return [zipURL]
            }
            return items
        }

        private static let logFileDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.locale = Locale.current
            f.timeZone = TimeZone.current
            return f
        }()

        private static let logZipDateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            f.locale = Locale.current
            f.timeZone = TimeZone.current
            return f
        }()

        private func createZipFile(items: [URL]) -> URL? {
            guard !items.isEmpty else { return nil }

            let zipTimestamp = Self.logZipDateFormatter.string(from: Date())

            let stagingDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("iaps-logs-\(zipTimestamp)", isDirectory: true)
            do {
                if fileManager.fileExists(atPath: stagingDir.path) {
                    try fileManager.removeItem(at: stagingDir)
                }
                try fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
                for url in items {
                    let attrs = try fileManager.attributesOfItem(atPath: url.path)
                    let creationDate = attrs[.creationDate] as? Date ?? Date()
                    let dateSuffix = Self.logFileDateFormatter.string(from: creationDate)
                    let stem = url.deletingPathExtension().lastPathComponent
                    let ext = url.pathExtension
                    let fileName = "iaps-\(stem)-\(dateSuffix).\(ext)"
                    try fileManager.copyItem(at: url, to: stagingDir.appendingPathComponent(fileName))
                }
            } catch {
                return nil
            }

            var zipURL: URL?
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(readingItemAt: stagingDir, options: .forUploading, error: &coordinatorError) { url in
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("iaps-logs-\(zipTimestamp).zip")
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.copyItem(at: url, to: dest)
                zipURL = dest
            }

            try? fileManager.removeItem(at: stagingDir)
            return zipURL
        }

        func uploadProfileAndSettings(_ force: Bool) {
            NSLog("SettingsState Upload Profile and Settings")
            nightscoutManager.uploadProfileAndSettings(force)
        }

        func uploadPreviousDayLog() {
            NSLog("SettingsState Upload Previous Day Log")
            nightscoutManager.uploadPreviousDayLog()
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
        allowDilution = settings.allowDilution
    }
}

struct Cleared {
    var entity: String = "Readings"
    var deleted: Bool = false
    let id = UUID()
}
