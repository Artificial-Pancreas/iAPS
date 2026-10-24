import Foundation
import KSCrashRecording

/// Opt-in crash reporting to open-iaps.app.
///
/// KSCrash is installed at launch with the smallest monitor set it allows: Mach
/// exceptions, signals, C++ and NSException as crash detectors, with the deadlock
/// watchdog (polls the main thread, false positives), zombie tracking (swizzles
/// dealloc) and memory-termination monitors off. KSCrash 2.6 force-enables its
/// "infrastructure" monitors on top of that — System, ApplicationState, UserInfo and
/// Resource — and the Resource one does run between crashes: a 1 Hz memory-footprint
/// read, a CPU-time poll (`proc_pidinfo`) every 5 s and a thread-list refresh every
/// 60 s, each a single syscall on its own queue. Nothing of this touches the loop
/// path, and the Resource monitor's own report type (non-fatal CPU-limit reports) is
/// disabled so every stored report is a real crash. At rest that is one thread parked
/// in a Mach wait plus ~1 MB of pre-allocated buffers.
///
/// Reports are written to disk by KSCrash while the process is dying and picked up on
/// the next launch, once the app's services are up. They leave the phone only when
/// "Send crash reports" is on in Sharing (default off) and the running version is the
/// latest main or dev release according to open-iaps.app's version check — crashes on
/// older builds may already be fixed and are not worth anyone's time. Nothing is ever
/// prompted: with the toggle off, pending reports are discarded silently.
///
/// What leaves the phone is a scrubbed copy of KSCrash's report (see `scrubbed`):
/// backtraces, register state, queue labels, the exception and its message, binary
/// names and UUIDs, device model, OS and app version. KSCrash also records things
/// the consent text does not cover — a raw window of the crashed thread's stack, the
/// object an NSException reason points at and its userInfo, a per-device hash, the
/// app's container path, time zone — and those are removed before serialisation.
/// Symbolication needs only the frames' addresses and the images' UUIDs and load
/// addresses, all of which stay.
final class CrashReportService {
    static let shared = CrashReportService()

    /// Most reports uploaded per launch; a crash loop must not turn into an upload storm.
    private static let maxReportsPerLaunch = 3

    private var installed = false
    private var processed = false

    private init() {}

    // MARK: - Install

    /// Call first thing in the App initialiser, and again from the launcher once
    /// protected data is available. Before the first unlock after a reboot the app
    /// cannot open its own files: KSCrash's `install` still succeeds then (it only
    /// fails when it cannot create its directories, and directories are not under
    /// data protection), but every file it sets up for the run — run id, console log,
    /// the System and Resource sidecars — fails silently, and a crash hours later in
    /// that background-launched process would be written without its system section.
    /// So the install waits for the same gate the launcher uses; on a normal launch
    /// the phone is unlocked and this still runs before anything else.
    func install() {
        guard !installed else { return }
        guard ProtectedDataGate.isAvailable() else {
            debug(.default, "Crash reporter install deferred: protected data is not available yet")
            return
        }

        let config = KSCrashConfiguration()
        config.monitors = [.machException, .signal, .cppException, .nsException, .system, .applicationState, .userInfo]
        config.enableQueueNameSearch = true // dispatch queue labels are the key iAPS diagnostic
        config.enableCPUExceptionReporting = false // the forced Resource monitor must not write reports
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
            // KSCrash 2.6 applies enableQueueNameSearch and then starts its thread cache,
            // whose init resets the flag to false (kstc_init runs after the configuration
            // is handled). Set it again afterwards or no report carries a queue label.
            kstc_setSearchQueueNames(true)
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
    @inline(never) static func simulateCrash() -> Never {
        let empty: [Int] = []
        let index = Int(Date().timeIntervalSince1970) & 0xFFFF
        _ = empty[index]
        fatalError("Simulated crash from Settings → Debug options")
    }

    /// Looks for reports written by a previous run. With the Sharing toggle off they are
    /// deleted; with it on they are uploaded if this build is a current release, and
    /// deleted on success. Failed uploads, and anything beyond the per-launch cap, stay
    /// for the next launch; KSCrash itself keeps at most 5 reports on disk (oldest
    /// pruned). Runs off the main thread; the only main-thread work is reading the setting.
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

        // Newest first, at most maxReportsPerLaunch; the rest wait for the next launch.
        let toSend = store.reportIDs.map(\.int64Value).sorted().suffix(Self.maxReportsPerLaunch)

        let appId = Token().getIdentifier()
        for id in toSend {
            guard let report = store.report(for: id),
                  let body = try? JSONSerialization.data(withJSONObject: Self.scrubbed(report.value))
            else {
                store.deleteReport(with: id)
                continue
            }
            if await send(body, appId: appId) {
                store.deleteReport(with: id)
            }
        }
    }

    // MARK: - Scrub

    /// Binary images under these prefixes are Apple's; their paths say nothing about the
    /// user and the server tells system images from app images by them.
    private static let systemImagePrefixes = ["/usr/lib/", "/System/", "/Developer/", "/private/preboot/"]

    /// Removes what the consent text does not cover, before the report is serialised:
    /// - `crash.threads[].stack` — KSCrash dumps a raw window of the crashed thread's
    ///   stack memory regardless of the introspection flag; `notable_addresses` likewise.
    /// - `crash.error.*.referenced_object` and `userInfo` — for an NSException KSCrash
    ///   dereferences any hex address in the reason string and dumps that object, and
    ///   stringifies the exception's userInfo (Core Data fills it with field values).
    /// - `system.device_app_hash` (a stable per-device identifier distinct from the
    ///   statistics id), `CFBundleExecutablePath`, `time_zone`, `boot_time`, `storage`,
    ///   `freeStorage`.
    /// - app binary paths reduced to their file name; the container path carries a
    ///   per-install UUID. System image paths are kept.
    /// Kept: backtraces (addresses, binary names and UUIDs), registers, queue labels,
    /// the exception type and its message, model, OS and app version.
    static func scrubbed(_ report: [String: Any]) -> [String: Any] {
        var out = report

        if var crash = out["crash"] as? [String: Any] {
            if let threads = crash["threads"] as? [[String: Any]] {
                crash["threads"] = threads.map { thread -> [String: Any] in
                    var t = thread
                    t.removeValue(forKey: "stack")
                    t.removeValue(forKey: "notable_addresses")
                    return t
                }
            }
            if let error = crash["error"] as? [String: Any] {
                crash["error"] = removing(keys: ["referenced_object", "userInfo"], from: error)
            }
            out["crash"] = crash
        }

        if var system = out["system"] as? [String: Any] {
            for key in ["device_app_hash", "CFBundleExecutablePath", "time_zone", "boot_time", "storage", "freeStorage"] {
                system.removeValue(forKey: key)
            }
            out["system"] = system
        }

        if let images = out["binary_images"] as? [[String: Any]] {
            out["binary_images"] = images.map { image -> [String: Any] in
                guard let name = image["name"] as? String,
                      !systemImagePrefixes.contains(where: { name.hasPrefix($0) })
                else { return image }
                var i = image
                i["name"] = (name as NSString).lastPathComponent
                return i
            }
        }

        return out
    }

    /// `dict` without `keys`, at any depth.
    private static func removing(keys: Set<String>, from dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in dict where !keys.contains(key) {
            if let nested = value as? [String: Any] {
                out[key] = removing(keys: keys, from: nested)
            } else {
                out[key] = value
            }
        }
        return out
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
