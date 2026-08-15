import UIKit

@MainActor enum ProtectedData {
    static var isAvailable: Bool {
        get async {
            UIApplication.shared.isProtectedDataAvailable
        }
    }

    nonisolated static let didBecomeAvailable = UIApplication.protectedDataDidBecomeAvailableNotification

    private static let probeName = "protection.test"

    private static var filesBecameReadable = false

    /// Whether the app can read its own Documents directory right now.
    static func canReadOwnFiles() -> Bool {
        if filesBecameReadable {
            return true
        }
        filesBecameReadable = probe()
        return filesBecameReadable
    }

    /// Suspends until `canReadOwnFiles()` is true. Returns immediately in the normal case.
    static func waitUntilFilesAreReadable() async {
        if canReadOwnFiles() {
            return
        }

        debug(.default, "Launch deferred: cannot read our own files yet (no unlock since boot)")

        // Polled rather than driven by `didBecomeAvailable`: the notification is the normal signal,
        // but one that arrives before we subscribe would leave the launch waiting forever, and this
        // cannot. The cost is one small read a second, only while the device has never been
        // unlocked and the app has nothing else to do.
        while !canReadOwnFiles() {
            try? await Task.sleep(for: .seconds(1))
        }

        debug(.default, "Our files became readable, resuming launch")
    }

    private static func probe() -> Bool {
        let fileManager = FileManager.default
        guard let documents = try? fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else {
            return false
        }

        let probeURL = documents.appendingPathComponent(probeName)

        if !fileManager.fileExists(atPath: probeURL.path) {
            try? Data("iAPS".utf8).write(to: probeURL, options: .completeFileProtectionUntilFirstUserAuthentication)
        }

        return (try? Data(contentsOf: probeURL)) != nil
    }
}
