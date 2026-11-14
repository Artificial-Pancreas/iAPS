import LoopKit
import UIKit

struct CgmDisplayInfo: Equatable, Sendable {
    let identifier: String
    let identifierForStatistics: String?
    let name: String
    let isOnboarded: Bool
    let image: UIImage?
    let pumpIsCgm: Bool
    let providesHeartbeat: Bool
    let allowCalibrations: Bool
    let appURL: URL?
    let glucoseUploadSupported: Bool
}

struct CgmDisplayStatus: Equatable, Sendable {
    let statusHighlight: String?
    /// the same highlight with its icon and level, nil without one
    let highlight: DeviceStatusHighlightDisplay?
    let sessionStartDate: Date?
    let shouldUploadGlucose: Bool
    let oneMinuteReadings: Bool
    let sensorDays: Double?
}

/// How serious a device's status highlight is: LoopKit's `DeviceStatusHighlightState`, for display.
enum DeviceStatusHighlightLevel: Equatable, Sendable {
    case normal
    case warning
    case critical
}

extension DeviceStatusHighlightLevel {
    init(_ state: DeviceStatusHighlightState) {
        switch state {
        case .critical: self = .critical
        case .warning: self = .warning
        case .normalCGM,
             .normalPump: self = .normal
        }
    }
}

/// A device manager's status highlight (LoopKit's `DeviceStatusHighlight`), for display.
struct DeviceStatusHighlightDisplay: Equatable, Sendable {
    let message: String
    /// an SF Symbol's name, as the device managers give it
    let imageName: String
    let level: DeviceStatusHighlightLevel
}

extension DeviceStatusHighlightDisplay {
    init?(_ highlight: DeviceStatusHighlight?) {
        guard let highlight else { return nil }
        self.init(
            message: highlight.localizedMessage,
            imageName: highlight.imageName,
            level: DeviceStatusHighlightLevel(highlight.state)
        )
    }

    static let fallbackSymbolName = "exclamationmark.circle.fill"

    /// The highlight's own symbol, or the fallback when there is no such SF Symbol.
    var symbolName: String {
        imageName.isEmpty || UIImage(systemName: imageName) == nil ? Self.fallbackSymbolName : imageName
    }
}
