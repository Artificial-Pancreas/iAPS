import Foundation
import MetricKit

/// Memory / process-pressure telemetry block attached to the statistics uploads.
///
/// Two tiers, matching the statistics sharing ladder:
/// - App-behaviour numbers (footprint, OS kill counts, JS-engine incidents) describe the
///   app, not the person or the phone, and ride along with BOTH the full Statistics
///   payload and the version-only ping.
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
        pressure_warnings = 0
        jetsam_exits = 0
        pressure_exits = 0
        watchdog_exits = 0
        webcontent_terminations = 0
        js_timeouts = 0
        crash_exits = nil
        normal_exits = nil
        other_exits = nil
    }
}

/// Collects the numbers behind `MemoryStats`.
///
/// `MetricKitService` owns the `MXMetricManager` subscription and feeds daily payloads in
/// via `processMetricPayload`; the app-side counters come from `increment` call sites.
///
/// MetricKit delivers its payloads at most once a day, covering the previous day, and
/// only on a real device — on the simulator the MetricKit-derived fields simply stay nil.
/// Because that delivery is late, MetricKit counts are filed into the bucket named by the
/// payload's own build metadata, not the build that happens to be running — an upgrade
/// therefore never swallows the previous build's last day of kills.
///
/// Everything here runs after `AppServices` has passed the protected-data gate: before
/// the first unlock after a reboot UserDefaults reads back empty, and writing the map
/// then would replace every stored bucket with a single fresh one.
enum MemoryMetricsService {
    enum Counter {
        case pressureWarnings
        case webContentTerminations
        case jsTimeouts
    }

    private static let storageKey = "MemoryMetrics_versionCounters"
    private static let latestPeakKey = "MemoryMetrics_peakFootprintMB"
    private static let processedPayloadsKey = "MemoryMetrics_processedPayloads"
    /// Old buckets freeze once their build stops running and the server has already
    /// ingested their totals, so retaining a handful bounds the payload without loss.
    private static let maxBuckets = 6
    private static let maxProcessedPayloads = 14

    private static let queue = DispatchQueue(label: "MemoryMetricsService.counters", qos: .utility)

    /// Called once by `MetricKitService.start()`. Materialises the running build's bucket
    /// immediately (zero-filled), so "this build ran and recorded no incidents" is an
    /// explicit row rather than an absence — otherwise a bucket only appears on the first
    /// incident or MetricKit payload, and a clean build is indistinguishable from one
    /// that never ran.
    static func start() {
        queue.async {
            mutateCurrentBucket { _ in }
        }
    }

    /// Files the event under the build that is running right now.
    static func increment(_ counter: Counter) {
        queue.async {
            mutateCurrentBucket { bucket in
                switch counter {
                case .pressureWarnings: bucket.pressure_warnings += 1
                case .webContentTerminations: bucket.webcontent_terminations += 1
                case .jsTimeouts: bucket.js_timeouts += 1
                }
            }
        }
    }

    static func snapshot(full: Bool) -> MemoryStats {
        let (counters, peak) = queue.sync {
            (loadMap(), UserDefaults.standard.object(forKey: latestPeakKey) as? Int)
        }

        var stats = MemoryStats(
            footprint_mb: FootprintLog.currentFootprintMB(),
            peak_mb: peak,
            counters: counters.isEmpty ? nil : counters
        )
        if full {
            stats.ram_mb = Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)
            stats.available_mb = Int(os_proc_available_memory()) / 1_048_576
        }
        debug(
            .service,
            "memory metrics snapshot: \(stats), ram_mb: \(Int(ProcessInfo.processInfo.physicalMemory / 1_048_576)), available_mb: \(Int(os_proc_available_memory()) / 1_048_576)"
        )
        return stats
    }

    /// Called by `MetricKitService` for each delivered payload. The numbers are read out
    /// here (MXMetricPayload is not Sendable and must not cross to the private queue) and
    /// only plain values are handed on.
    static func processMetricPayload(_ payload: MXMetricPayload) {
        // The payload names the build it describes; file under that build so a day's
        // counts that arrive after an upgrade still land where they happened. MetricKit
        // knows version + build number but not the commit, so this resolves to the
        // bucket for that (version, build) — the newest one if several exist.
        let target: BucketTarget? = payload.metaData.map {
            BucketTarget(version: payload.latestApplicationVersion, build: $0.applicationBuildVersion)
        }

        let exits: ExitCounts? = payload.applicationExitMetrics.map { metrics in
            let fg = metrics.foregroundExitData
            let bg = metrics.backgroundExitData
            return ExitCounts(
                jetsam: fg.cumulativeMemoryResourceLimitExitCount + bg.cumulativeMemoryResourceLimitExitCount,
                pressure: bg.cumulativeMemoryPressureExitCount,
                watchdog: fg.cumulativeAppWatchdogExitCount + bg.cumulativeAppWatchdogExitCount,
                crashes: fg.cumulativeAbnormalExitCount + bg.cumulativeAbnormalExitCount
                    + fg.cumulativeBadAccessExitCount + bg.cumulativeBadAccessExitCount
                    + fg.cumulativeIllegalInstructionExitCount + bg.cumulativeIllegalInstructionExitCount,
                normal: fg.cumulativeNormalAppExitCount + bg.cumulativeNormalAppExitCount,
                other: bg.cumulativeCPUResourceLimitExitCount // background-only in MetricKit: no fg counterpart
                    + bg.cumulativeBackgroundTaskAssertionTimeoutExitCount
                    + bg.cumulativeSuspendedWithLockedFileExitCount
            )
        }
        let peakMB = payload.memoryMetrics.map {
            Int($0.peakMemoryUsage.converted(to: .megabytes).value.rounded())
        }

        let period = periodKey(payload.timeStampBegin, payload.timeStampEnd)
        queue.async {
            record(period: period, target: target, exits: exits, peakMB: peakMB)
        }
    }

    /// The (version, build) a MetricKit payload says it describes.
    private struct BucketTarget {
        let version: String
        let build: String
    }

    private struct ExitCounts {
        let jetsam: Int
        let pressure: Int
        let watchdog: Int
        let crashes: Int
        let normal: Int
        let other: Int
    }

    // MARK: - Payload accounting (private queue)

    private static func record(period: String, target: BucketTarget?, exits: ExitCounts?, peakMB: Int?) {
        // MetricKit re-delivers payloads, and the counters are monotonic and diffed
        // server-side, so counting one twice inflates that build's totals permanently.
        guard claimPayload(period) else {
            debug(.service, "MetricKit payload \(period) already counted, skipping")
            return
        }

        if let exits {
            // Always file, even all-zero: once an exit payload has been seen for the
            // build, crash/normal read 0 ("counted, none") instead of nil ("not counted").
            mutateBucket(matching: target) { bucket in
                bucket.jetsam_exits += exits.jetsam
                bucket.pressure_exits += exits.pressure
                bucket.watchdog_exits += exits.watchdog
                bucket.crash_exits = (bucket.crash_exits ?? 0) + exits.crashes
                bucket.normal_exits = (bucket.normal_exits ?? 0) + exits.normal
                bucket.other_exits = (bucket.other_exits ?? 0) + exits.other
            }
        }
        if let peakMB {
            UserDefaults.standard.set(peakMB, forKey: latestPeakKey)
            mutateBucket(matching: target) { bucket in
                bucket.peak_mb = max(bucket.peak_mb ?? 0, peakMB)
            }
        }
    }

    /// Records the payload period as counted, or reports that it already was.
    private static func claimPayload(_ period: String) -> Bool {
        var seen = UserDefaults.standard.stringArray(forKey: processedPayloadsKey) ?? []
        guard !seen.contains(period) else { return false }

        seen.append(period)
        if seen.count > maxProcessedPayloads {
            seen.removeFirst(seen.count - maxProcessedPayloads)
        }
        UserDefaults.standard.set(seen, forKey: processedPayloadsKey)
        return true
    }

    /// Identifies a payload by the period it reports on — the same thing the payload's
    /// file name is derived from, and stable across re-delivery of the same payload.
    private static func periodKey(_ begin: Date, _ end: Date) -> String {
        "\(Int(begin.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))"
    }

    // MARK: - Bucket storage (private queue)

    /// The running build's identity, read once: "<branch> <sha>" from branch.txt, and the
    /// bundle's build date, which tells builds apart when branch.txt is missing.
    private static let runningBranch = Bundle.main.gitBranch
    private static let runningBuilt = Bundle.main.buildDate

    /// Mutate the bucket for the build that is running right now, creating it if needed.
    private static func mutateCurrentBucket(_ change: (inout MemoryVersionCounters) -> Void) {
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
        matching target: BucketTarget?,
        _ change: (inout MemoryVersionCounters) -> Void
    ) {
        guard let target, bucketKey(version: target.version, build: target.build) != currentBucketKey else {
            mutateCurrentBucket(change)
            return
        }

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
        let base = currentBucketKey
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
    /// be evicted in the same call that filed its counts.
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

    /// The running build's base key. Both parts come from Info.plist, so it is fixed for
    /// the lifetime of the process.
    private static let currentBucketKey = bucketKey(
        version: Bundle.main.releaseVersionNumber,
        build: Bundle.main.buildVersionNumber ?? "0"
    )

    /// Sortable release order: version numbers first, build number last. Only the
    /// "version(build)" part is parsed — a suffix is not part of the release.
    /// Unparseable keys sort oldest.
    private static func releaseOrder(_ key: String) -> [Int] {
        let head = key.split(separator: " ").first.map(String.init) ?? key
        let parts = head.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return parts.isEmpty ? [-1] : parts
    }
}
