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
    /// Peak footprint over the last MetricKit reporting day, MB.
    var peak_mb: Int?
    /// UIKit memory-pressure warnings received, cumulative since install.
    var pressure_warnings: Int?
    /// OS kills for exceeding the app's own memory limit (jetsam), fg+bg, cumulative.
    var jetsam_exits: Int?
    /// OS kills of the backgrounded app to relieve system-wide memory pressure, cumulative.
    var pressure_exits: Int?
    /// Watchdog kills (unresponsive main thread), cumulative.
    var watchdog_exits: Int?
    /// WebContent (oref JS) process deaths detected by WebViewScriptExecutor, cumulative.
    var webcontent_terminations: Int?
    /// JS call attempts that hit the WebViewScriptExecutor watchdog timeout, cumulative.
    /// One wedged loop cycle can add up to 3 (initial attempt + retries).
    var js_timeouts: Int?
    /// Physical RAM of the device, MB. Full statistics only.
    var ram_mb: Int?
    /// Memory iOS will still allow this app right now, MB. Full statistics only.
    var available_mb: Int?
}

/// Collects the numbers behind `MemoryStats`.
///
/// MetricKit delivers its payloads at most once a day, covering the previous day, and
/// only on a real device — on the simulator the MetricKit-derived fields simply stay nil.
/// The exit counts are accumulated into monotonic totals; the server diffs successive
/// uploads to get per-interval rates, which keeps this class free of upload-state
/// bookkeeping (an upload that never happens loses nothing).
final class MemoryMetricsService: NSObject, MXMetricManagerSubscriber {
    static let shared = MemoryMetricsService()

    enum Keys {
        static let pressureWarnings = "MemoryMetrics_pressureWarnings"
        static let jetsamExits = "MemoryMetrics_jetsamExits"
        static let pressureExits = "MemoryMetrics_pressureExits"
        static let watchdogExits = "MemoryMetrics_watchdogExits"
        static let peakFootprintMB = "MemoryMetrics_peakFootprintMB"
        static let webContentTerminations = "MemoryMetrics_webContentTerminations"
        static let jsTimeouts = "MemoryMetrics_jsTimeouts"
    }

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
            Self.increment(Keys.pressureWarnings)
        }
    }

    /// Static so call sites (WebViewScriptExecutor) don't need the singleton started first.
    static func increment(_ key: String) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    func snapshot(full: Bool) -> MemoryStats {
        let defaults = UserDefaults.standard
        var stats = MemoryStats(
            footprint_mb: Self.currentFootprintMB(),
            peak_mb: defaults.object(forKey: Keys.peakFootprintMB) as? Int,
            pressure_warnings: defaults.integer(forKey: Keys.pressureWarnings),
            jetsam_exits: defaults.integer(forKey: Keys.jetsamExits),
            pressure_exits: defaults.integer(forKey: Keys.pressureExits),
            watchdog_exits: defaults.integer(forKey: Keys.watchdogExits),
            webcontent_terminations: defaults.integer(forKey: Keys.webContentTerminations),
            js_timeouts: defaults.integer(forKey: Keys.jsTimeouts)
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
            if let exits = payload.applicationExitMetrics {
                let fg = exits.foregroundExitData
                let bg = exits.backgroundExitData
                add(
                    fg.cumulativeMemoryResourceLimitExitCount + bg.cumulativeMemoryResourceLimitExitCount,
                    to: Keys.jetsamExits
                )
                add(bg.cumulativeMemoryPressureExitCount, to: Keys.pressureExits)
                add(
                    fg.cumulativeAppWatchdogExitCount + bg.cumulativeAppWatchdogExitCount,
                    to: Keys.watchdogExits
                )
            }
            if let memory = payload.memoryMetrics {
                let mb = Int(memory.peakMemoryUsage.converted(to: .megabytes).value.rounded())
                UserDefaults.standard.set(mb, forKey: Keys.peakFootprintMB)
            }
        }
    }

    // MARK: - Internals

    /// Each MetricKit payload's counts cover only that payload's day, so summing
    /// successive payloads yields a correct running total.
    private func add(_ count: Int, to key: String) {
        guard count > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: key) + count, forKey: key)
    }

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
