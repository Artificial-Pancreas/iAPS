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
    /// Incident counters, bucketed by the release they occurred under, so a
    /// release-over-release comparison never smears events across an upgrade.
    /// Keys are "version(build)" composites ("8.3.5(274)") — build number alone is
    /// ambiguous because plain Xcode builds don't increment it, and version alone
    /// can't separate two builds of the same release. The newest 6 buckets are retained.
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
/// `MetricKitService` owns the `MXMetricManager` subscription and feeds daily payloads in
/// via `processMetricPayload`; the app-side counters come from `increment` call sites.
///
/// MetricKit delivers its payloads at most once a day, covering the previous day, and
/// only on a real device — on the simulator the MetricKit-derived fields simply stay nil.
/// Because that delivery is late, MetricKit counts are filed into the bucket named by the
/// payload's own build metadata, not the build that happens to be running — an upgrade
/// therefore never swallows the previous build's last day of kills.
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

    static func increment(_ counter: Counter) {
        let key = currentBucketKey
        queue.async {
            mutateBucket(key: key) { bucket in
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
            footprint_mb: currentFootprintMB(),
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
        // The payload names the release it describes; use it so a day's counts that
        // arrive after an upgrade still land on the build they happened under.
        let key: String
        if let build = payload.metaData?.applicationBuildVersion {
            key = bucketKey(version: payload.latestApplicationVersion, build: build)
        } else {
            key = currentBucketKey
        }

        var jetsam = 0
        var pressure = 0
        var watchdog = 0
        if let exits = payload.applicationExitMetrics {
            let fg = exits.foregroundExitData
            let bg = exits.backgroundExitData
            jetsam = fg.cumulativeMemoryResourceLimitExitCount + bg.cumulativeMemoryResourceLimitExitCount
            pressure = bg.cumulativeMemoryPressureExitCount
            watchdog = fg.cumulativeAppWatchdogExitCount + bg.cumulativeAppWatchdogExitCount
        }
        let peakMB = payload.memoryMetrics.map {
            Int($0.peakMemoryUsage.converted(to: .megabytes).value.rounded())
        }

        let period = periodKey(payload.timeStampBegin, payload.timeStampEnd)
        queue.async {
            record(period: period, key: key, jetsam: jetsam, pressure: pressure, watchdog: watchdog, peakMB: peakMB)
        }
    }

    // MARK: - Payload accounting (private queue)

    private static func record(
        period: String,
        key: String,
        jetsam: Int,
        pressure: Int,
        watchdog: Int,
        peakMB: Int?
    ) {
        // MetricKit re-delivers payloads, and the counters are monotonic and diffed
        // server-side, so counting one twice inflates that build's totals permanently.
        guard claimPayload(period) else {
            debug(.service, "MetricKit payload \(period) already counted, skipping")
            return
        }

        if jetsam + pressure + watchdog > 0 {
            mutateBucket(key: key) { bucket in
                bucket.jetsam_exits += jetsam
                bucket.pressure_exits += pressure
                bucket.watchdog_exits += watchdog
            }
        }
        if let peakMB {
            UserDefaults.standard.set(peakMB, forKey: latestPeakKey)
            mutateBucket(key: key) { bucket in
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

    private static func mutateBucket(
        key: String,
        _ change: (inout MemoryVersionCounters) -> Void
    ) {
        var map = loadMap()
        var bucket = map[key] ?? MemoryVersionCounters()
        change(&bucket)
        map[key] = bucket

        // Prune oldest buckets (release order: version tuple, then build) beyond the cap.
        if map.count > maxBuckets {
            let sorted = map.keys.sorted {
                releaseOrder($0).lexicographicallyPrecedes(releaseOrder($1))
            }
            for key in sorted.prefix(map.count - maxBuckets) {
                map.removeValue(forKey: key)
            }
        }

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

    /// "8.3.5(274)" — version alone collides across builds of one release, build alone
    /// collides across releases (plain Xcode builds don't increment it).
    private static func bucketKey(version: String?, build: String) -> String {
        "\(version ?? "?")(\(build))"
    }

    /// The running build's key. Both parts come from Info.plist, so it is fixed for the
    /// lifetime of the process.
    private static let currentBucketKey = bucketKey(
        version: Bundle.main.releaseVersionNumber,
        build: Bundle.main.buildVersionNumber ?? "0"
    )

    /// Sortable release order for pruning: version numbers first, build number last.
    /// Unparseable keys sort oldest (pruned first).
    private static func releaseOrder(_ key: String) -> [Int] {
        let parts = key.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
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
