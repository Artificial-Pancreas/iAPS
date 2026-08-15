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
    /// Peak footprint over the last MetricKit reporting day, MB (any version).
    var peak_mb: Int?
    /// Incident counters, bucketed by the build number they occurred under, so a
    /// release-over-release comparison never smears events across an upgrade.
    /// Keys are build numbers ("274"); the newest 6 buckets are retained.
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
    /// Marketing version ("8.3.5") for display; the dictionary key is the build number.
    var version: String?
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

    init(version: String?) {
        self.version = version
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
    /// Files the event under the currently running build.
    static func increment(_ counter: Counter) {
        mutateBucket(build: currentBuild(), version: currentVersion()) { bucket in
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
            // The payload names the build it describes; use it so a day's counts that
            // arrive after an upgrade still land on the build they happened under.
            let build = payload.metaData?.applicationBuildVersion ?? Self.currentBuild()
            let version = payload.latestApplicationVersion

            if let exits = payload.applicationExitMetrics {
                let fg = exits.foregroundExitData
                let bg = exits.backgroundExitData
                let jetsam = fg.cumulativeMemoryResourceLimitExitCount + bg.cumulativeMemoryResourceLimitExitCount
                let pressure = bg.cumulativeMemoryPressureExitCount
                let watchdog = fg.cumulativeAppWatchdogExitCount + bg.cumulativeAppWatchdogExitCount
                if jetsam + pressure + watchdog > 0 {
                    Self.mutateBucket(build: build, version: version) { bucket in
                        bucket.jetsam_exits += jetsam
                        bucket.pressure_exits += pressure
                        bucket.watchdog_exits += watchdog
                    }
                }
            }
            if let memory = payload.memoryMetrics {
                let mb = Int(memory.peakMemoryUsage.converted(to: .megabytes).value.rounded())
                UserDefaults.standard.set(mb, forKey: Self.latestPeakKey)
                Self.mutateBucket(build: build, version: version) { bucket in
                    bucket.peak_mb = max(bucket.peak_mb ?? 0, mb)
                }
            }
        }
    }

    // MARK: - Bucket storage

    private static func mutateBucket(
        build: String,
        version: String?,
        _ change: (inout MemoryVersionCounters) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        var map = loadMap()
        var bucket = map[build] ?? MemoryVersionCounters(version: version)
        if bucket.version == nil {
            bucket.version = version
        }
        change(&bucket)
        map[build] = bucket

        // Prune oldest buckets (numeric build order, string fallback) beyond the cap.
        if map.count > maxBuckets {
            let sorted = map.keys.sorted {
                switch (Int($0), Int($1)) {
                case let (.some(a), .some(b)): return a < b
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return $0 < $1
                }
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

    private static func currentBuild() -> String {
        Bundle.main.buildVersionNumber ?? "0"
    }

    private static func currentVersion() -> String? {
        Bundle.main.releaseVersionNumber
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
