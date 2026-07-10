import CoreData
import SwiftUI

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var fileManager: FileManager!
        @Injected() private var profileAndSettingsUploadManager: ProfileAndSettingsUploadManager!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var databaseManager: DatabaseManager!

        @Setting(\.closedLoop) var closedLoop = false
        @Setting(\.debugOptions) var debugOptions = false
        @Setting(\.profileID) var profileID: String = "Hypo Treatment"
        @Setting(\.allowDilution) var allowDilution = false
        @Setting(\.extended_overrides) var extended_overrides = false
        @Setting(\.noCarbs) var noCarbs = false
        @Setting(\.allowOneMinuteLoop) var allowOneMinuteLoop = false
        @Setting(\.allowOneMinuteGlucose) var allowOneMinuteGlucose = false

        @Published var entities: [Cleared] = CoreDataStack.shared.persistentContainer.managedObjectModel.entities
            .compactMap(\.name).map {
                Cleared(entity: $0, deleted: false)
            }

        private(set) var buildNumber = Bundle.main.buildVersionNumber ?? "Unknown"
        private(set) var versionNumber = Bundle.main.releaseVersionNumber ?? "Unknown"
        private(set) var branch = StateModel.readBranch()
        private(set) var copyrightNotice = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

        override func subscribe() async {}

        private static func readBranch() -> String {
            guard let url = Bundle.main.url(forResource: "branch", withExtension: "txt"),
                  let content = try? String(contentsOf: url)
            else { return "Unknown" }
            for line in content.components(separatedBy: .newlines) {
                let components = line.components(separatedBy: "=")
                if components.count == 2, components[0].trimmingCharacters(in: .whitespaces) == "BRANCH" {
                    return components[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return "Unknown"
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
            Task {
                debug(.default, "SettingsState Upload Profile and Settings")
                await profileAndSettingsUploadManager.uploadProfileAndSettings(force: force)
            }
        }

        func uploadPreviousDayLog() {
            Task {
                debug(.default, "SettingsState Upload Previous Day Log")
                await databaseManager.uploadPreviousDayLog()
            }
        }

        func hideSettingsModal() {
            hideModal()
        }

        func deleteOverrides() {
            Task {
                await nightscoutManager.deleteAllNSoverrrides() // For testing
            }
        }
    }
}

struct Cleared {
    var entity: String = "Readings"
    var deleted: Bool = false
    let id = UUID()
}
