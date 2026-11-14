import LoopKit
import UIKit

struct PumpDisplayInfo: Equatable, @unchecked Sendable {
    let identifier: String
    let name: String
    let isOnboarded: Bool
    let image: UIImage?
    let expiresAt: Date?
    let podActivatedAt: Date?
    /// the pod or patch can deliver (`KnownPlugins.isDeliveryUnitActive`); true for pumps without one
    let deliveryUnitActive: Bool
}

struct PumpDisplayStatus: Equatable, Sendable {
    enum StatusType: String, JSON {
        case normal
        case suspended
        case bolusing
    }

    let status: StatusType

    let reservoir: ReservoirReading?
    let statusHighlight: String?
    let timeZone: TimeZone
    let battery: Battery?
    let deliveryIsUncertain: Bool
    let isSuspended: Bool
    /// the temp basal the pump reports as running, nil when it reports none
    let tempBasal: TempBasalDisplay?
    let isBolusing: Bool
    let supportedBasalRates: [Double]
    let supportedBolusVolumes: [Double]
    let model: String? // only for medtronic pumps, oref0 uses this value to enable 0.025U basal rate granularity for pumps that support it

    let timestamp: Date
}

/// A running temp basal as the pump manager reports it, for display only.
struct TempBasalDisplay: Equatable, Sendable {
    let rate: Decimal
    let startDate: Date
    let endDate: Date
}

extension TempBasalDisplay {
    /// the temp basal of a pump manager's basal delivery state, nil for every other state
    init?(basalDeliveryState: PumpManagerStatus.BasalDeliveryState?) {
        guard case let .tempBasal(dose) = basalDeliveryState else { return nil }
        // the pump's rates are multiples of 0.001 U/hr at the finest: this drops the Double's binary noise
        let rate = Decimal((dose.unitsPerHour * 1000).rounded()) / 1000
        self.init(rate: rate, startDate: dose.startDate, endDate: dose.endDate)
    }
}

enum ReservoirReading: Sendable, Equatable {
    case units(Decimal)
    case aboveThreshold
}

extension ReservoirReading {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        switch self {
        case .aboveThreshold: return ["aboveThreshold": true]
        case let .units(units): return ["units": units.description]
        }
    }

    var knownValue: Decimal? {
        switch self {
        case .aboveThreshold: return nil
        case let .units(units): return units
        }
    }

    init?(from: RawValue?) {
        guard let from else { return nil }
        if from["aboveThreshold"] as? Bool == true {
            self = .aboveThreshold
        } else if let unitsString = from["units"] as? String {
            if let units = unitsString.toDecimal {
                self = .units(units)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
