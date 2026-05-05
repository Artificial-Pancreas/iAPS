import Combine
import Foundation
import MetricKit

/// Receives MetricKit crash diagnostics on next app launch after a crash,
/// queues them for upload, and publishes state for the UI to present a consent alert.
final class CrashReportService: NSObject, ObservableObject {
    @Published private(set) var pendingCount: Int = 0

    private let storageKey = "io.openIAPS.pendingCrashPayloads"
    private var pendingPayloads: [Data] = []

    override init() {
        super.init()
        if let stored = UserDefaults.standard.array(forKey: storageKey) as? [Data], !stored.isEmpty {
            pendingPayloads = stored
            pendingCount = stored.count
        }
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    /// Upload all pending crash payloads then clear them.
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

    private func clear() {
        pendingPayloads = []
        pendingCount = 0
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}

extension CrashReportService: MXMetricManagerSubscriber {
    func didReceive(_: [MXMetricPayload]) {}

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashes = payloads.compactMap(\.crashDiagnostics).flatMap { $0 }
        guard !crashes.isEmpty else { return }

        let jsonPayloads = crashes.map { $0.jsonRepresentation() }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingPayloads.append(contentsOf: jsonPayloads)
            self.pendingCount = self.pendingPayloads.count
            UserDefaults.standard.set(self.pendingPayloads, forKey: self.storageKey)
        }
    }
}
