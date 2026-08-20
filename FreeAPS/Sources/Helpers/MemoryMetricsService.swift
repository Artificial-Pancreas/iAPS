import Foundation
import MetricKit
import UIKit
import os

/// Memory / process-pressure telemetry block attached to the statistics uploads.
///
/// Two tiers, matching the statistics sharing ladder:
/// - App-behaviour numbers (footprint, OS kill counts, JS-engine incidents) describe the
///   app, not the person or the phone, and ride along with BOTH the full Statistics
///   payload and the BareMinimum version ping.
/// - Hardware-derived numbers (device RAM, remaining per-app allowance) narrow down the
///   phone model class, so they are only included at the full statistics level, where
///   the model is shared anyway.
struct MemoryStats: JSON, Equatable {
    /// Physical footprint of the app process right now, MB.
    var footprint_mb: Int?
    /// Peak footprint over the last MetricKit reporting day, MB (any release).
    var peak_mb: Int?
    /// Incident counters, bucketed by the build they occurred under, so a
    /// release-over-release comparison never smears events across an upgrade.
    /// Keys are "version(build)" composites ("8.3.5(274)"), unique per device; the
    /// commit each bucket was built from is recorded inside the bucket (`branch`),
    /// which is what aggregates across devices. The newest 6 buckets are retained.
    var counters: [String: MemoryVersionCounters]?
    /// Physical RAM of the device, MB. Full statistics only.
    var ram_mb: Int?
    /// Memory iOS will still allow this app right now, MB. Full statistics only.
    var available_mb: Int?
}

/// One build's worth of incident counts. Counters start at zero when that build first
/// runs and only ever grow, so the latest uploaded value IS the build's total —
/// no server-side diffing needed for per-version numbers.
struct MemoryVersionCounters: JSON, Equatable {
    /// "<branch> <sha>" the build came from (branch.txt), e.g. "dev 81a532e" — the
    /// code identity that is comparable across devices. Build numbers are not: each
    /// builder's Actions run counter differs and local Xcode builds stay at 1.
    var branch: String?
    /// When this bucket was created, i.e. when this build first ran on the device.
    /// Lets the server turn counts into rates (incidents per day on that build).
    var since: Date?
    /// Highest MetricKit daily peak recorded while this build ran, MB.
    var peak_mb: Int?
    /// UIKit memory-pressure warnings received.
    var pressure_warnings: Int
    /// OS kills for exceeding the app's own memory limit (jetsam), fg+bg.
    var jetsam_exits: Int
    /// OS kills of the backgrounded app to relieve system-wide memory pressure.
    var pressure_exits: Int
    /// Watchdog kills (unresponsive main thread).
    var watchdog_exits: Int
    /// WebContent (oref JS) process deaths detected by WebViewScriptExecutor.
    var webcontent_terminations: Int
    /// JS call attempts that hit the WebViewScriptExecutor watchdog timeout.
    /// One wedged loop cycle can add up to 3 (initial attempt + retries).
    var js_timeouts: Int

    init() {
        branch = nil
        since = nil
        peak_mb = nil
        pressure_warnings = 0
        jetsam_exits = 0
        pressure_exits = 0
        watchdog_exits = 0
        webcontent_terminations = 0
        js_timeouts = 0
    }
}

/// Collects the numbers behind `MemoryStats`.
///
/// MetricKit delivers its payloads at most once a day, covering the previous day, and
/// only on a real device — on the simulator the MetricKit-derived fields simply stay nil.
/// Because that delivery is late, MetricKit counts are filed into the bucket named by the
/// payload's own build metadata, not the build that happens to be running — an upgrade
/// therefore never swallows the previous build's last day of kills.
final class MemoryMetricsService: NSObject, MXMetricManagerSubscriber {
    static let shared = MemoryMetricsService()

    enum Counter {
        case pressureWarnings
        case jetsamExits
        case pressureExits
        case watchdogExits
        case webContentTerminations
        case jsTimeouts
    }

    private static let storageKey = "MemoryMetrics_versionCounters"
    private static let latestPeakKey = "MemoryMetrics_peakFootprintMB"
    /// Old buckets freeze once their build stops running and the server has already
    /// ingested their totals, so retaining a handful bounds the payload without loss.
    private static let maxBuckets = 6
    private static let lock = NSLock()

    override private init() {
        super.init()
    }

    /// Call once at app start.
    func start() {
        MXMetricManager.shared.add(self)
        // Materialise the running build's bucket immediately (zero-filled), so
        // "this build ran and recorded no incidents" is an explicit row rather than
        // an absence — otherwise a bucket only appears on the first incident or
        // MetricKit payload, and a clean build is indistinguishable from one that
        // never ran.
        Self.mutateCurrentBucket { _ in }
        // Foundation-qualified: the app defines its own NotificationCenter protocol for DI.
        Foundation.NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { _ in
            MemoryMetricsService.increment(.pressureWarnings)
        }
    }

    /// Static so call sites (WebViewScriptExecutor) don't need the singleton started first.
    /// Files the event under the currently running release.
    static func increment(_ counter: Counter) {
        mutateCurrentBucket { bucket in
            switch counter {
            case .pressureWarnings: bucket.pressure_warnings += 1
            case .jetsamExits: bucket.jetsam_exits += 1
            case .pressureExits: bucket.pressure_exits += 1
            case .watchdogExits: bucket.watchdog_exits += 1
            case .webContentTerminations: bucket.webcontent_terminations += 1
            case .jsTimeouts: bucket.js_timeouts += 1
            }
        }
    }

    func snapshot(full: Bool) -> MemoryStats {
        Self.lock.lock()
        let counters = Self.loadMap()
        Self.lock.unlock()

        var stats = MemoryStats(
            footprint_mb: Self.currentFootprintMB(),
            peak_mb: UserDefaults.standard.object(forKey: Self.latestPeakKey) as? Int,
            counters: counters.isEmpty ? nil : counters
        )
        if full {
            stats.ram_mb = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
            stats.available_mb = Int(os_proc_available_memory()) / 1_048_576
        }
        return stats
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            // The payload names the build it describes; file under that build so a day's
            // counts that arrive after an upgrade still land where they happened. MetricKit
            // knows version + build number but not the commit, so this resolves to the
            // bucket for that (version, build) — the newest one if several exist.
            let target: (version: String, build: String)? = payload.metaData
                .map { (payload.latestApplicationVersion, $0.applicationBuildVersion) }

            if let exits = payload.applicationExitMetrics {
                let fg = exits.foregroundExitData
                let bg = exits.backgroundExitData
                let jetsam = fg.cumulativeMemoryResourceLimitExitCount + bg.cumulativeMemoryResourceLimitExitCount
                let pressure = bg.cumulativeMemoryPressureExitCount
                let watchdog = fg.cumulativeAppWatchdogExitCount + bg.cumulativeAppWatchdogExitCount
                if jetsam + pressure + watchdog > 0 {
                    Self.mutateBucket(matching: target) { bucket in
                        bucket.jetsam_exits += jetsam
                        bucket.pressure_exits += pressure
                        bucket.watchdog_exits += watchdog
                    }
                }
            }
            if let memory = payload.memoryMetrics {
                let mb = Int(memory.peakMemoryUsage.converted(to: .megabytes).value.rounded())
                UserDefaults.standard.set(mb, forKey: Self.latestPeakKey)
                Self.mutateBucket(matching: target) { bucket in
                    bucket.peak_mb = max(bucket.peak_mb ?? 0, mb)
                }
            }
        }
    }

    // MARK: - Bucket storage

    /// Mutate the bucket for the build that is running right now, creating it if needed.
    ///
    /// The bucket key is "version(build)". That is unique for Actions builds (the run
    /// counter increments) but a local Xcode build keeps build number 1 across commits,
    /// so the key alone would merge different code into one bucket. Hence: if the key's
    /// bucket exists but was created from a different commit, this build gets its own
    /// bucket keyed "version(build) sha". A bucket that predates the `branch` field
    /// (earlier instrumented builds) is adopted by the running commit.
    private static func mutateCurrentBucket(_ change: (inout MemoryVersionCounters) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        var map = loadMap()
        let base = currentBucketKey()
        let branch = Bundle.main.gitBranch
        let key: String
        if let existing = map[base], let owner = existing.branch, let branch, owner != branch {
            // Same version + build number, different commit — a local rebuild.
            let sha = branch.split(separator: " ").last.map(String.init) ?? branch
            key = "\(base) \(sha)"
        } else {
            key = base
        }
        mutate(&map, key: key, branch: branch, change)
        store(map)
    }

    /// Mutate the bucket for a (version, build) named by a MetricKit payload — the newest
    /// bucket carrying that composite, or a fresh one if none exists. Falls back to the
    /// running build when the payload has no metadata.
    private static func mutateBucket(
        matching target: (version: String, build: String)?,
        _ change: (inout MemoryVersionCounters) -> Void
    ) {
        guard let target else {
            mutateCurrentBucket(change)
            return
        }
        lock.lock()
        defer { lock.unlock() }

        var map = loadMap()
        let base = bucketKey(version: target.version, build: target.build)
        let candidates = map.filter { $0.key == base || $0.key.hasPrefix(base + " ") }
        let key = candidates.max { ($0.value.since ?? .distantPast) < ($1.value.since ?? .distantPast) }?.key ?? base
        // A brand-new bucket for the running build can be stamped with the running commit;
        // one for an older build cannot (we don't know it), the server resolves that from history.
        let branch = base == currentBucketKey() ? Bundle.main.gitBranch : nil
        mutate(&map, key: key, branch: branch, change)
        store(map)
    }

    /// Caller holds `lock`.
    private static func mutate(
        _ map: inout [String: MemoryVersionCounters],
        key: String,
        branch: String?,
        _ change: (inout MemoryVersionCounters) -> Void
    ) {
        var bucket = map[key] ?? MemoryVersionCounters()
        if bucket.since == nil { bucket.since = Date() }
        if bucket.branch == nil { bucket.branch = branch }
        change(&bucket)
        map[key] = bucket

        // Prune oldest buckets beyond the cap: version tuple, then build number, then age.
        if map.count > maxBuckets {
            let sorted = map.sorted { a, b in
                let ra = releaseOrder(a.key), rb = releaseOrder(b.key)
                if ra != rb { return ra.lexicographicallyPrecedes(rb) }
                return (a.value.since ?? .distantPast) < (b.value.since ?? .distantPast)
            }
            for entry in sorted.prefix(map.count - maxBuckets) {
                map.removeValue(forKey: entry.key)
            }
        }
    }

    /// Caller holds `lock`.
    private static func store(_ map: [String: MemoryVersionCounters]) {
        if let data = try? JSONCoding.encoder.encode(map) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private static func loadMap() -> [String: MemoryVersionCounters] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let map = try? JSONCoding.decoder.decode([String: MemoryVersionCounters].self, from: data)
        else {
            return [:]
        }
        return map
    }

    /// "8.3.5(274)" — version + build number, unique per device.
    private static func bucketKey(version: String?, build: String) -> String {
        "\(version ?? "?")(\(build))"
    }

    private static func currentBucketKey() -> String {
        bucketKey(version: Bundle.main.releaseVersionNumber, build: Bundle.main.buildVersionNumber ?? "0")
    }

    /// Sortable release order for pruning: version numbers first, build number last.
    /// Only the "version(build)" part is parsed — a sha suffix is not a number.
    /// Unparseable keys sort oldest (pruned first).
    private static func releaseOrder(_ key: String) -> [Int] {
        let head = key.split(separator: " ").first.map(String.init) ?? key
        let parts = head.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return parts.isEmpty ? [-1] : parts
    }

    // MARK: - Gauges

    private static func currentFootprintMB() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint / 1_048_576)
    }
}
