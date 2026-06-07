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

    let pumpManagerStatus: PumpManagerStatus

    let timestamp: Date?
}
