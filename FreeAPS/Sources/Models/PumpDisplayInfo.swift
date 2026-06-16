import LoopKit
import UIKit

struct PumpDisplayInfo: Equatable, @unchecked Sendable {
    let identifier: String
    let name: String
    let isOnboarded: Bool
    let image: UIImage?
    let expiresAt: Date?
    let podActivatedAt: Date?
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
    let isBolusing: Bool
    let supportedBasalRates: [Double]
    let supportedBolusVolumes: [Double]

    let timestamp: Date
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

    private static let parsingLocale = Locale(identifier: "en_US_POSIX")

    init?(from: RawValue?) {
        guard let from else { return nil }
        if from["aboveThreshold"] as? Bool == true {
            self = .aboveThreshold
        } else if let unitsString = from["units"] as? String {
            if let units = Decimal(string: unitsString, locale: Self.parsingLocale) {
                self = .units(units)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
}
