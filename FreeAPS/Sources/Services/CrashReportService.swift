import Foundation
import KSCrashRecording

/// Installs KSCrash signal handlers at startup, collects crash reports from the previous
/// session on next launch, and queues them for upload with user consent.
final class CrashReportService: NSObject, ObservableObject {
    @Published private(set) var pendingCount: Int = 0

    private let storageKey = "io.openIAPS.pendingCrashPayloads"
    private var pendingPayloads: [Data] = []

    override init() {
        super.init()

        // Install crash handlers as early as possible.
        // KSCrash installs Mach exception and POSIX signal handlers; they are idle until a crash.
        let config = KSCrashConfiguration()
        try? KSCrash.shared.install(with: config)

        // Reload any reports that were captured and stored but not yet uploaded
        // (e.g., user dismissed the alert, app relaunched).
        if let stored = UserDefaults.standard.array(forKey: storageKey) as? [Data], !stored.isEmpty {
            pendingPayloads = stored
            pendingCount = stored.count
        }

        // Harvest any new crash reports written by the previous session.
        harvestPendingReports()
    }

    // MARK: - Public

    /// Upload all queued crash reports then clear local storage.
    func uploadAndDismiss() {
        let payloads = pendingPayloads
        clear()

        let appId = Token().getIdentifier()
        let baseURL = IAPSconfig.statURL

        for payload in payloads {
            var components = URLComponents()
            components.scheme = baseURL.scheme
            components.host = baseURL.host
            components.port = baseURL.port
            components.path = "/api/v1/upload/crash"
            guard let url = components.url else { continue }

            var request = URLRequest(url: url, timeoutInterval: 60)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(appId, forHTTPHeaderField: "X-App-Id")
            request.httpBody = payload

            URLSession.shared.dataTask(with: request).resume()
        }
    }

    /// Discard pending reports without uploading.
    func dismiss() {
        clear()
    }

    // MARK: - Private

    private func harvestPendingReports() {
        guard let store = KSCrash.shared.reportStore else { return }
        let ids = store.reportIDs
        guard !ids.isEmpty else { return }

        var newPayloads: [Data] = []
        for idNum in ids {
            let reportID = idNum.int64Value
            if let report = store.report(for: reportID),
               let data = try? JSONSerialization.data(withJSONObject: report.value)
            {
                newPayloads.append(data)
            }
        }
        // Delete from KSCrash's internal store immediately; we own them now.
        store.deleteAllReports()

        guard !newPayloads.isEmpty else { return }

        pendingPayloads.append(contentsOf: newPayloads)
        pendingCount = pendingPayloads.count
        UserDefaults.standard.set(pendingPayloads, forKey: storageKey)
    }

    private func clear() {
        pendingPayloads = []
        pendingCount = 0
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
