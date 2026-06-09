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

    let statusHighlight: String?
    let timeZone: TimeZone
    let battery: Battery?
    let deliveryIsUncertain: Bool
    let isSuspended: Bool
    let isBolusing: Bool
    let supportedBasalRates: [Double]
    let supportedBolusVolumes: [Double]

    let timestamp: Date?
}

enum ReservoirReading: Sendable, Equatable {
    case units(Decimal)
    case aboveThreshold
}
