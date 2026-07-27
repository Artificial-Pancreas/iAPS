import Foundation
import MetricKit

/// Subscribes to MetricKit and stores each daily payload (cumulative CPU time,
/// foreground/background time, network transfer, exit reasons, ...) as a JSON file
/// under Documents/metrickit/, so battery cost can be compared across builds.
///
/// Crash diagnostics additionally become `LoopEvent`s, so a crash the user never noticed
/// shows up on the main chart and in the events history.
///
/// Payloads arrive at most once per 24h, shortly after an app launch.
/// For a quick look without waiting a day: run attached to Xcode and use
/// Debug -> Simulate MetricKit Payloads (physical device only).
final class MetricKitService: NSObject, MXMetricManagerSubscriber, AppServiceSync, @unchecked Sendable {
    private let storage: FileStorage
    private let loopEventsStorage: LoopEventsStorage

    init(storage: FileStorage, loopEventsStorage: LoopEventsStorage) {
        self.storage = storage
        self.loopEventsStorage = loopEventsStorage
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    /// daily metrics (aggregates)
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            save(payload.jsonRepresentation(), as: fileName("metrics", payload.timeStampBegin, payload.timeStampEnd))
            debug(.service, "MetricKit metrics payload: \(summary(payload))")
        }
    }

    /// diagnostics (crashes, hangs, cpu exceptions, disk write exceptions)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            save(payload.jsonRepresentation(), as: fileName("diagnostics", payload.timeStampBegin, payload.timeStampEnd))
            debug(.service, "MetricKit diagnostics payload: \(payload.timeStampBegin) .. \(payload.timeStampEnd)")

            recordCrashes(payload)
        }
    }

    /// A crash the user never saw (iOS relaunches the app in the background) leaves no trace otherwise.
    /// The payload has no per-crash timestamp, so the end of the period it covers is the best estimate.
    private func recordCrashes(_ payload: MXDiagnosticPayload) {
        let crashes = payload.crashDiagnostics ?? []
        guard crashes.isNotEmpty else { return }

        let timestamp = payload.timeStampEnd
        for (index, crash) in crashes.enumerated() {
            // payloads can be re-delivered - a stable id keeps the event unique
            let event = LoopEvent(
                id: "crash-\(timestamp.timeIntervalSince1970)-\(index)",
                timestamp: timestamp,
                type: .appCrashed,
                message: Self.describe(crash)
            )
            debug(.service, "MetricKit crash diagnostic: \(event.message ?? "")")
            Task { [loopEventsStorage] in
                await loopEventsStorage.recordCrash(event)
            }
        }
    }

    private static func describe(_ crash: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let reason = crash.terminationReason {
            parts.append(reason)
        }
        if let exceptionType = crash.exceptionType {
            parts.append("exception \(exceptionType)")
        }
        if let exceptionCode = crash.exceptionCode {
            parts.append("code \(exceptionCode)")
        }
        if let signal = crash.signal {
            parts.append("signal \(signal)")
        }
        return parts.isNotEmpty ?
            parts.joined(separator: ", ") :
            NSLocalizedString("The app was restarted by iOS", comment: "Crash loop event")
    }

    private func save(_ json: Data, as name: String) {
        guard let string = String(data: json, encoding: .utf8) else { return }
        Task { [storage] in
            await storage.save(string, as: name)
        }
    }

    // file names derived from the payload period -> re-delivery overwrites the same file
    private func fileName(_ kind: String, _ begin: Date, _ end: Date) -> String {
        "metrickit/\(kind)-\(Self.stamp.string(from: begin))--\(Self.stamp.string(from: end)).json"
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()

    /// one-line log digest of the numbers we care about for the battery comparison
    private func summary(_ payload: MXMetricPayload) -> String {
        var parts: [String] = ["\(payload.timeStampBegin) .. \(payload.timeStampEnd)"]

        if let cpu = payload.cpuMetrics {
            parts.append("cpu \(Int(cpu.cumulativeCPUTime.converted(to: .seconds).value))s")
        }
        if let time = payload.applicationTimeMetrics {
            let fg = time.cumulativeForegroundTime.converted(to: .minutes).value
            let bg = time.cumulativeBackgroundTime.converted(to: .minutes).value
            parts.append("fg \(Int(fg))m")
            parts.append("bg \(Int(bg))m")
        }
        if let network = payload.networkTransferMetrics {
            let cellular = network.cumulativeCellularDownload + network.cumulativeCellularUpload
            let wifi = network.cumulativeWifiDownload + network.cumulativeWifiUpload
            parts.append("cell \(Int(cellular.converted(to: .kilobytes).value))KB")
            parts.append("wifi \(Int(wifi.converted(to: .kilobytes).value))KB")
        }
        if let exits = payload.applicationExitMetrics?.backgroundExitData {
            let kills = exits.cumulativeMemoryPressureExitCount
                + exits.cumulativeMemoryResourceLimitExitCount
                + exits.cumulativeCPUResourceLimitExitCount
                + exits.cumulativeBackgroundTaskAssertionTimeoutExitCount
            parts.append("bg exits: \(exits.cumulativeNormalAppExitCount) normal, \(kills) killed")
        }

        return parts.joined(separator: ", ")
    }
}
