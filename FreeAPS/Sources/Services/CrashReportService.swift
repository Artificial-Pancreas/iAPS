import Foundation
import KSCrashRecording

/// Opt-in crash reporting to open-iaps.app.
///
/// KSCrash is installed at launch with the smallest useful monitor set — Mach exceptions,
/// signals, C++ and NSException — and nothing that runs between crashes: no deadlock
/// watchdog (polls the main thread, false positives), no zombie tracking (swizzles
/// dealloc), no memory/termination monitors. At rest that is one thread parked in a
/// Mach wait plus ~1 MB of pre-allocated buffers; nothing executes on the loop path.
///
/// Reports are written to disk by KSCrash while the process is dying and picked up on
/// the next launch, once the app's services are up. They leave the phone only when
/// "Send crash reports" is on in Sharing (default off) and the running version is the
/// latest main or dev release according to open-iaps.app's version check — crashes on
/// older builds may already be fixed and are not worth anyone's time. Nothing is ever
/// prompted: with the toggle off, pending reports are discarded silently.
///
/// A report contains thread stacks, register state, binary names and UUIDs, device
/// model, OS and app version. No glucose, no settings, no identifiers beyond the
/// anonymous statistics id the upload is filed under.
final class CrashReportService {
    static let shared = CrashReportService()

    /// Most reports uploaded per launch; a crash loop must not turn into an upload storm.
    private static let maxReportsPerLaunch = 3

    private var installed = false
    private var processed = false

    private init() {}

    // MARK: - Install (call first thing in the App initialiser)

    func install() {
        guard !installed else { return }
        installed = true

        let config = KSCrashConfiguration()
        config.monitors = [.machException, .signal, .cppException, .nsException, .system, .applicationState, .userInfo]
        config.enableQueueNameSearch = true // dispatch queue labels are the key iAPS diagnostic
        config.enableMemoryIntrospection = false
        config.addConsoleLogToReport = false
        config.enableSwiftAsyncStackTraces = false
        // Stamped into every report: the commit is the identity of the code that crashed.
        config.userInfoJSON = [
            "branch": Self.gitBranch() ?? "",
            "app_version": Bundle.main.releaseVersionNumber ?? "",
            "build_number": Bundle.main.buildVersionNumber ?? ""
        ]

        do {
            try KSCrash.shared.install(with: config)
        } catch {
            warning(.default, "Crash reporter did not install: \(error.localizedDescription)")
        }
    }

    // MARK: - Harvest + upload (call once the app's services exist)

    /// Looks for reports written by a previous run. With the Sharing toggle off they are
    /// deleted; with it on they are uploaded if this build is a current release, and
    /// deleted on success. Failed uploads stay for the next launch. Runs off the main
    /// thread; the only main-thread work is reading the setting.
    func processPendingReports(enabled: Bool) {
        guard installed, !processed else { return }
        processed = true
        guard let store = KSCrash.shared.reportStore, store.reportCount > 0 else { return }

        guard enabled else {
            debug(.default, "Crash reports found (\(store.reportCount)) but crash reporting is off — discarding")
            store.deleteAllReports()
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            await self?.upload(from: store)
        }
    }

    private func upload(from store: KSCrashReportStore) async {
        let version = Bundle.main.releaseVersionNumber ?? ""
        guard await isCurrentRelease(version) else {
            debug(
                .default,
                "Crash reports not uploaded: \(version) is not the latest main or dev release — discarding"
            )
            store.deleteAllReports()
            return
        }

        let ids = store.reportIDs.map(\.int64Value).sorted()
        let toSend = ids.suffix(Self.maxReportsPerLaunch)
        for id in ids where !toSend.contains(id) {
            store.deleteReport(with: id)
        }

        let appId = Token().getIdentifier()
        for id in toSend {
            guard let report = store.report(for: id),
                  let body = try? JSONSerialization.data(withJSONObject: report.value)
            else {
                store.deleteReport(with: id)
                continue
            }
            if await send(body, appId: appId) {
                store.deleteReport(with: id)
            }
        }
    }

    private func send(_ body: Data, appId: String) async -> Bool {
        var request = URLRequest(url: Self.endpoint("/api/v1/upload/crash"), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")
        request.httpBody = body
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            debug(.default, "Crash report upload: HTTP \(status)")
            return (200 ..< 300).contains(status)
        } catch {
            warning(.default, "Crash report upload failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Latest main / dev release per open-iaps.app. Network failure → not current: better
    /// to keep the report for the next launch than to upload one nobody will read.
    private func isCurrentRelease(_ version: String) async -> Bool {
        struct Versions: Decodable { let main: String; let dev: String }
        guard !version.isEmpty else { return false }
        var request = URLRequest(url: Self.endpoint("/api/v1/version_check"), timeoutInterval: 20)
        request.allowsConstrainedNetworkAccess = true
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let latest = try JSONDecoder().decode(Versions.self, from: data)
            return version == latest.main || version == latest.dev
        } catch {
            warning(.default, "Crash report version check failed: \(error.localizedDescription)")
            return false
        }
    }

    /// "<branch-or-tag> <short sha>" from branch.txt, written by the build phase (same
    /// value the statistics upload reports as `Branch`). Nil when missing or malformed.
    private static func gitBranch() -> String? {
        guard let url = Bundle.main.url(forResource: "branch", withExtension: "txt"),
              let content = try? String(contentsOf: url)
        else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "=")
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "BRANCH" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func endpoint(_ path: String) -> URL {
        var components = URLComponents()
        components.scheme = IAPSconfig.statURL.scheme
        components.host = IAPSconfig.statURL.host
        components.port = IAPSconfig.statURL.port
        components.path = path
        return components.url!
    }
}
