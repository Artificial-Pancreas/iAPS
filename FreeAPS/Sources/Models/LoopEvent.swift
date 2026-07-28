import Foundation
import LoopKit
import SwiftUI

/// A recorded loop-cycle failure or device problem.
struct LoopEvent: JSON, Identifiable, Equatable, Hashable {
    let id: String
    let timestamp: Date
    let type: LoopEventType
    let message: String?

    init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        type: LoopEventType,
        message: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.message = message
    }
}

enum LoopEventType: String, Codable, Sendable, CaseIterable {
    case pumpBusy
    case pumpSuspended
    case pumpNotConfigured
    case pumpCommunication
    case glucoseData
    /// oref0 failed to produce a recommendation
    case algorithm
    /// a manual temp basal was running
    case manualTempBasal
    /// the recommendation was not enacted because the bolus view was open
    case bolusView
    /// a loop failure that doesn't fit any of the categories above
    case loopFailed

    case pumpError
    /// the pump manager reported an error in its configuration
    case pumpConfiguration
    /// the pump reported a device error state (occlusion, empty reservoir, ...)
    case pumpDeviceState
    case cgmError
    case deliveryUncertain
    case deliveryResolved

    case appStart
    case appCrashed

    case skippedLoops
    case other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LoopEventType(rawValue: raw) ?? .other
    }
}

extension LoopEventType {
    /// when we have a cluster of events on the chart, this is used to pick the most severe one
    var severity: Int {
        switch self {
        case .deliveryUncertain: return 100
        case .appCrashed: return 95
        case .pumpDeviceState: return 90
        case .pumpCommunication,
             .pumpError: return 80
        case .pumpConfiguration,
             .pumpNotConfigured: return 70
        case .algorithm,
             .loopFailed: return 60
        case .skippedLoops: return 50
        case .cgmError,
             .glucoseData: return 40
        case .pumpBusy,
             .pumpSuspended: return 30
        case .bolusView,
             .manualTempBasal: return 20
        case .appStart,
             .deliveryResolved,
             .other: return 10
        }
    }

    var title: String {
        switch self {
        case .pumpBusy: return NSLocalizedString("Pump busy", comment: "Loop event")
        case .pumpSuspended: return NSLocalizedString("Pump suspended", comment: "Loop event")
        case .pumpNotConfigured: return NSLocalizedString("Pump not configured", comment: "Loop event")
        case .pumpCommunication: return NSLocalizedString("Pump communication failed", comment: "Loop event")
        case .glucoseData: return NSLocalizedString("Glucose data problem", comment: "Loop event")
        case .algorithm: return NSLocalizedString("Recommendation failed", comment: "Loop event")
        case .manualTempBasal: return NSLocalizedString("Manual temp basal", comment: "Loop event")
        case .bolusView: return NSLocalizedString("Not enacted (bolus view)", comment: "Loop event")
        case .loopFailed: return NSLocalizedString("Loop failed", comment: "Loop event")
        case .pumpError: return NSLocalizedString("Pump error", comment: "Loop event")
        case .pumpConfiguration: return NSLocalizedString("Pump configuration error", comment: "Loop event")
        case .pumpDeviceState: return NSLocalizedString("Pump device error", comment: "Loop event")
        case .cgmError: return NSLocalizedString("CGM error", comment: "Loop event")
        case .deliveryUncertain: return NSLocalizedString("Delivery uncertain", comment: "Loop event")
        case .deliveryResolved: return NSLocalizedString("Delivery confirmed", comment: "Loop event")
        case .appStart: return NSLocalizedString("App started", comment: "Loop event")
        case .appCrashed: return NSLocalizedString("App crashed", comment: "Loop event")
        case .skippedLoops: return NSLocalizedString("Skipped loops", comment: "Loop event")
        case .other: return NSLocalizedString("Event", comment: "Loop event")
        }
    }

    var symbol: String {
        switch self {
        case .pumpBusy: return "hourglass"
        case .pumpSuspended: return "pause.circle.fill"
        case .pumpNotConfigured: return "questionmark.circle.fill"
        case .pumpCommunication: return "antenna.radiowaves.left.and.right.slash"
        case .glucoseData: return "drop.triangle.fill"
        case .algorithm: return "function"
        case .manualTempBasal: return "hand.raised.fill"
        case .bolusView: return "syringe.fill"
        case .loopFailed: return "exclamationmark.arrow.triangle.2.circlepath"
        case .pumpError: return "exclamationmark.triangle.fill"
        case .pumpConfiguration: return "gearshape.fill"
        case .pumpDeviceState: return "cross.case.fill"
        case .cgmError: return "waveform.slash"
        case .deliveryUncertain: return "questionmark.diamond.fill"
        case .deliveryResolved: return "checkmark.diamond.fill"
        case .appStart: return "power"
        case .appCrashed: return "bolt.trianglebadge.exclamationmark.fill"
        case .skippedLoops: return "circle.dotted"
        case .other: return "circle.fill"
        }
    }

    enum Status {
        case critical
        case warning
        case informational
        case good
    }

    var status: Status {
        switch self {
        case .appCrashed,
             .deliveryUncertain,
             .pumpCommunication,
             .pumpDeviceState,
             .pumpError:
            return .critical
        case .algorithm,
             .cgmError,
             .glucoseData,
             .loopFailed,
             .pumpConfiguration,
             .pumpNotConfigured,
             .skippedLoops:
            return .warning
        case .appStart,
             .bolusView,
             .manualTempBasal,
             .other,
             .pumpBusy,
             .pumpSuspended:
            return .informational
        case .deliveryResolved:
            return .good
        }
    }

    var color: Color { status.color }
    var canBeDismissed: Bool { self == .appStart }
}

extension LoopEventType.Status {
    var color: Color {
        switch self {
        case .critical:
            return Self.dynamic(light: (0.702, 0.149, 0.118), dark: (1.000, 0.420, 0.420))
        case .warning:
            return Self.dynamic(light: (0.941, 0.635, 0.008), dark: (1.000, 0.690, 0.125))
        case .informational:
            return Self.dynamic(light: (0.475, 0.475, 0.498), dark: (0.620, 0.620, 0.643))
        case .good:
            return Self.dynamic(light: (0.180, 0.490, 0.196), dark: (0.298, 0.851, 0.392))
        }
    }

    private static func dynamic(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(UIColor { traits in
            let (red, green, blue) = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: red, green: green, blue: blue, alpha: 1)
        })
    }
}

extension LoopEvent {
    /// a loop cycle failure vs a rejected enactment, so that the chart/list can tell apart
    /// "pump was busy" from "couldn't talk to the pump" etc.
    ///
    /// Returns `nil` when the failure is a pump command that `BaseDeviceDataManager` has already recorded.
    static func failure(_ error: Error, timestamp: Date = Date()) -> LoopEvent? {
        guard !isRecordedAsCommandFailure(error) else { return nil }
        return LoopEvent(
            timestamp: timestamp,
            type: LoopEventType(failure: error),
            message: error.localizedDescription
        )
    }

    private static func isRecordedAsCommandFailure(_ error: Error) -> Bool {
        if let apsError = error as? APSError, case .pumpError = apsError {
            return true
        }
        return error is PumpManagerError
    }
}

extension LoopEventType {
    init(failure error: Error) {
        if let apsError = error as? APSError {
            switch apsError {
            case let .pumpError(underlying):
                self = LoopEventType(pumpManagerError: underlying) ?? .pumpCommunication
            case let .invalidPumpState(message):
                self = message.lowercased().contains("suspend") ? .pumpSuspended : .pumpNotConfigured
            case .pumpNotConfigured:
                self = .pumpNotConfigured
            case .bolusInProgress:
                self = .pumpBusy
            case .glucoseError:
                self = .glucoseData
            case .apsError:
                self = .algorithm
            case .deviceSyncError:
                self = .pumpCommunication
            case .manualBasalTemp:
                self = .manualTempBasal
            case .activeBolusViewBasal,
                 .activeBolusViewBasalandBolus,
                 .activeBolusViewBolus:
                self = .bolusView
            }
        } else if let type = LoopEventType(pumpManagerError: error) {
            self = type
        } else {
            self = .loopFailed
        }
    }

    /// `nil` when the error is not a `PumpManagerError`
    init?(pumpManagerError error: Error) {
        guard let pumpError = error as? PumpManagerError else { return nil }
        switch pumpError {
        case .configuration:
            self = .pumpConfiguration
        case .communication,
             .connection:
            self = .pumpCommunication
        case .deviceState:
            self = .pumpDeviceState
        case .uncertainDelivery:
            self = .deliveryUncertain
        }
    }
}
