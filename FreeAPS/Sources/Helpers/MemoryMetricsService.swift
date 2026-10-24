import Foundation
import MetricKit
import os
import UIKit

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
    /// Nil when the bucket was created by a late MetricKit payload about an older build
    /// — we don't know when that build started running.
    var since: Date?
    /// When the build was compiled (the bundle's build date). Tells two builds apart
    /// when branch.txt is missing; nil for buckets of builds that aren't running.
    var built: Date?
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
    /// Crashes proper, fg+bg: MetricKit's abnormal (uncaught exception / abort),
    /// bad-access (SIGSEGV/SIGBUS) and illegal-instruction exits. Optional so a bucket
    /// written by a build that did not count them reads as "unknown", not zero.
    var crash_exits: Int?
    /// Clean exits, fg+bg: the user swiped the app away, or iOS ended a suspended
    /// process normally. The control group for `crash_exits`: a relaunch seen in the
    /// log with neither a crash nor a kill behind it was one of these.
    var normal_exits: Int?
    /// The remaining ways iOS ends a process, which are neither a crash nor a memory
    /// kill: CPU-limit kills (fg+bg), background-task-assertion timeouts and
    /// suspended-with-locked-file kills (bg). With crash/normal/jetsam/pressure/watchdog
    /// this accounts for every MXAppExitMetric class.
    var other_exits: Int?

    init() {
        branch = nil
        since = nil
        built = nil
        peak_mb = nil
        crash_exits = nil
        normal_exits = nil
        other_exits = nil
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

    /// Call once, after `ProtectedDataGate` has passed — before the first unlock after a
    /// reboot UserDefaults reads back empty, and writing the map then would replace every
    /// stored bucket with a single fresh one.
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
            footprint_mb: FootprintLog.currentFootprintMB(),
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
                let crashes = fg.cumulativeAbnormalExitCount + bg.cumulativeAbnormalExitCount
                    + fg.cumulativeBadAccessExitCount + bg.cumulativeBadAccessExitCount
                    + fg.cumulativeIllegalInstructionExitCount + bg.cumulativeIllegalInstructionExitCount
                let normal = fg.cumulativeNormalAppExitCount + bg.cumulativeNormalAppExitCount
                let other = bg.cumulativeCPUResourceLimitExitCount // background-only in MetricKit: no fg counterpart
                    + bg.cumulativeBackgroundTaskAssertionTimeoutExitCount
                    + bg.cumulativeSuspendedWithLockedFileExitCount
                // Always file, even all-zero: once an exit payload has been seen for the
                // build, crash/normal read 0 ("counted, none") instead of nil ("not counted").
                Self.mutateBucket(matching: target) { bucket in
                    bucket.jetsam_exits += jetsam
                    bucket.pressure_exits += pressure
                    bucket.watchdog_exits += watchdog
                    bucket.crash_exits = (bucket.crash_exits ?? 0) + crashes
                    bucket.normal_exits = (bucket.normal_exits ?? 0) + normal
                    bucket.other_exits = (bucket.other_exits ?? 0) + other
                }
            }
            if let memory = payload.memoryMetrics, ProtectedDataGate.isAvailable() {
                let mb = Int(memory.peakMemoryUsage.converted(to: .megabytes).value.rounded())
                UserDefaults.standard.set(mb, forKey: Self.latestPeakKey)
                Self.mutateBucket(matching: target) { bucket in
                    bucket.peak_mb = max(bucket.peak_mb ?? 0, mb)
                }
            }
        }
    }

    // MARK: - Bucket storage

    /// The running build's identity, read once: "<branch> <sha>" from branch.txt, and the
    /// bundle's build date, which tells builds apart when branch.txt is missing.
    private static let runningBranch = Bundle.main.gitBranch
    private static let runningBuilt = Bundle.main.buildDate

    /// Mutate the bucket for the build that is running right now, creating it if needed.
    private static func mutateCurrentBucket(_ change: (inout MemoryVersionCounters) -> Void) {
        guard ProtectedDataGate.isAvailable() else { return }
        lock.lock()
        defer { lock.unlock() }

        var map = loadMap()
        let key = currentKey(in: map)
        var bucket = map[key] ?? MemoryVersionCounters()
        if bucket.since == nil { bucket.since = Date() }
        if bucket.branch == nil { bucket.branch = runningBranch }
        if bucket.built == nil { bucket.built = runningBuilt }
        change(&bucket)
        map[key] = bucket
        prune(&map, keeping: [key])
        store(map)
    }

    /// Mutate the bucket for a (version, build) named by a MetricKit payload — the newest
    /// bucket carrying that composite, or a fresh one if none exists. A payload about the
    /// running build (or without metadata) goes to the running build's bucket.
    private static func mutateBucket(
        matching target: (version: String, build: String)?,
        _ change: (inout MemoryVersionCounters) -> Void
    ) {
        guard let target, bucketKey(version: target.version, build: target.build) != currentBucketKey() else {
            mutateCurrentBucket(change)
            return
        }
        guard ProtectedDataGate.isAvailable() else { return }
        lock.lock()
        defer { lock.unlock() }

        var map = loadMap()
        let base = bucketKey(version: target.version, build: target.build)
        let candidates = map.filter { $0.key == base || $0.key.hasPrefix(base + " ") }
        let key = candidates.max { ($0.value.since ?? .distantPast) < ($1.value.since ?? .distantPast) }?.key ?? base
        // A fresh bucket for an older build gets no `since`, `branch` or `built`: we don't
        // know when it started running or what it was built from. The server resolves the
        // commit from the device's history.
        var bucket = map[key] ?? MemoryVersionCounters()
        change(&bucket)
        map[key] = bucket
        prune(&map, keeping: [currentKey(in: map), key])
        store(map)
    }

    /// The running build's bucket key. "version(build)" is unique for Actions builds (the
    /// run counter increments), but a local Xcode build keeps build number 1 across commits,
    /// so when that key already belongs to different code the running build gets
    /// "version(build) <sha>" instead — or "version(build) built-<unix time>" when there is
    /// no branch.txt to name the commit. A bucket the running build already owns, under
    /// either form of key, is always reused: once the older bucket holding the base key
    /// has been pruned, the base key must not look free again, or the running build's
    /// counts would split over two buckets.
    private static func currentKey(in map: [String: MemoryVersionCounters]) -> String {
        let base = currentBucketKey()
        if let existing = map[base], isRunningBuild(existing) { return base }
        if let owned = map.first(where: { $0.key.hasPrefix(base + " ") && isRunningBuild($0.value) }) {
            return owned.key
        }
        guard map[base] != nil else { return base }
        if let runningBranch {
            return "\(base) \(sha(of: runningBranch))"
        }
        return "\(base) built-\(Int(runningBuilt.timeIntervalSince1970))"
    }

    /// Whether a bucket belongs to the running build: the same commit when both know it
    /// (compared by sha — the same commit under another branch or tag name is the same
    /// code), else the same build date. A bucket with neither predates identity recording
    /// and is adopted by the running build.
    private static func isRunningBuild(_ bucket: MemoryVersionCounters) -> Bool {
        if let owner = bucket.branch, let runningBranch {
            return sha(of: owner) == sha(of: runningBranch)
        }
        if let built = bucket.built {
            // Stored dates round-trip through ISO 8601, so allow for lost sub-second precision.
            return abs(built.timeIntervalSince(runningBuilt)) < 1
        }
        return bucket.branch == nil
    }

    /// "dev 81a532e" → "81a532e".
    private static func sha(of branch: String) -> String {
        branch.split(separator: " ").last.map(String.init) ?? branch
    }

    /// Drop the oldest buckets beyond the cap, oldest-created first, and never the running
    /// build's nor the bucket just written. Sorting by release order instead would evict the
    /// running build after a downgrade, or for a local build (build number 1) among Actions
    /// builds of the same version. Buckets without `since` (legacy, or older builds seen
    /// only via MetricKit) go first, earliest release first — which is why a bucket a late
    /// MetricKit payload has just created is exempt: it has no `since` and would otherwise
    /// be evicted in the same call that filed its counts. Caller holds `lock`.
    private static func prune(_ map: inout [String: MemoryVersionCounters], keeping kept: Set<String>) {
        guard map.count > maxBuckets else { return }
        let sorted = map.filter { !kept.contains($0.key) }.sorted { a, b in
            let sa = a.value.since ?? .distantPast, sb = b.value.since ?? .distantPast
            if sa != sb { return sa < sb }
            return releaseOrder(a.key).lexicographicallyPrecedes(releaseOrder(b.key))
        }
        for entry in sorted.prefix(map.count - maxBuckets) {
            map.removeValue(forKey: entry.key)
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

    /// Sortable release order: version numbers first, build number last. Only the
    /// "version(build)" part is parsed — a suffix is not part of the release.
    /// Unparseable keys sort oldest.
    private static func releaseOrder(_ key: String) -> [Int] {
        let head = key.split(separator: " ").first.map(String.init) ?? key
        let parts = head.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return parts.isEmpty ? [-1] : parts
    }
}
