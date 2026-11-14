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
