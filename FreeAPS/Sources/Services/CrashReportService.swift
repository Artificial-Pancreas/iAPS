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

    // MARK: - Install

    /// Call first thing in the App initialiser, and again once protected data is
    /// available. Before the first unlock after a reboot KSCrash may not be able to
    /// create its report directory; a failed install is retried at that point rather
    /// than leaving the process without crash handlers for its whole lifetime.
    func install() {
        guard !installed else { return }

        let config = KSCrashConfiguration()
        config.monitors = [.machException, .signal, .cppException, .nsException, .system, .applicationState, .userInfo]
        config.enableQueueNameSearch = true // dispatch queue labels are the key iAPS diagnostic
        config.enableMemoryIntrospection = false
        config.addConsoleLogToReport = false
        config.enableSwiftAsyncStackTraces = false
        // Stamped into every report: the commit is the identity of the code that crashed.
        config.userInfoJSON = [
            "branch": Bundle.main.gitBranch ?? "",
            "app_version": Bundle.main.releaseVersionNumber ?? "",
            "build_number": Bundle.main.buildVersionNumber ?? ""
        ]

        do {
            try KSCrash.shared.install(with: config)
            installed = true
        } catch {
            warning(.default, "Crash reporter did not install: \(error.localizedDescription)")
        }
    }

    // MARK: - Harvest + upload (call once the app's services exist)

    // MARK: - Test hook (Settings → Debug options)

    /// A real crash through the installed handlers rather than a call into KSCrash, so
    /// the whole path is exercised: report written while dying, found at the next
    /// launch, uploaded if the Sharing toggle is on.
    ///
    /// Trips a Swift runtime bounds check rather than calling fatalError: the optimiser
    /// tail-calls fatalError and inlines small callers, so the first such test crash
    /// reported no app frame at all. A `brk` inside this function puts it at the top of
    /// the stack, which is also what a real force-unwrap or index failure looks like
    /// (EXC_BREAKPOINT / SIGTRAP). The index is opaque to the compiler so the check
    /// cannot be folded away.
    @inline(never)
    static func simulateCrash() -> Never {
        let empty: [Int] = []
        let index = Int(Date().timeIntervalSince1970) & 0xFFFF
        _ = empty[index]
        fatalError("Simulated crash from Settings → Debug options")
    }

    /// Looks for reports written by a previous run. With the Sharing toggle off they are
    /// deleted; with it on they are uploaded if this build is a current release, and
    /// deleted on success. Failed uploads stay for the next launch. Runs off the main
    /// thread; the only main-thread work is reading the setting.
    func processPendingReports(enabled: Bool) {
        guard installed, !processed else { return }
        processed = true

        Task.detached(priority: .utility) { [weak self] in
            guard let store = KSCrash.shared.reportStore, store.reportCount > 0 else { return }
            guard enabled else {
                debug(.default, "Crash reports found (\(store.reportCount)) but crash reporting is off — discarding")
                store.deleteAllReports()
                return
            }
            await self?.upload(from: store)
        }
    }

    private func upload(from store: CrashReportStore) async {
        let version = Bundle.main.releaseVersionNumber ?? ""
        switch await releaseStatus(of: version) {
        case .current:
            break
        case .outdated:
            debug(
                .default,
                "Crash reports not uploaded: \(version) is not the latest main or dev release — discarding"
            )
            store.deleteAllReports()
            return
        case .unknown:
            debug(.default, "Crash reports kept for the next launch: the release check did not answer")
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

    private enum ReleaseStatus {
        case current
        case outdated
        case unknown
    }

    /// Whether `version` is the latest main or dev release per open-iaps.app. Only a
    /// definite "outdated" discards reports; when the check gets no answer (offline,
    /// server down) they stay for the next launch — the upload would fail the same way.
    private func releaseStatus(of version: String) async -> ReleaseStatus {
        guard !version.isEmpty else { return .outdated }
        var latest: Version?
        // fetchVersion turns failures into an empty Version rather than an error.
        do {
            for try await value in NightscoutAPI(url: IAPSconfig.statURL).fetchVersion().values {
                latest = value
                break
            }
        } catch {
            latest = nil
        }
        guard let latest, !latest.main.isEmpty || !latest.dev.isEmpty else { return .unknown }
        return version == latest.main || version == latest.dev ? .current : .outdated
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
