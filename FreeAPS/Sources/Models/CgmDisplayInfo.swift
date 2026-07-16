import UIKit

struct CgmDisplayInfo: Equatable, Sendable {
    let identifier: String
    let identifierForStatistics: String?
    let name: String
    let isOnboarded: Bool
    let image: UIImage?
    let pumpIsCgm: Bool
    let providesHeartbeat: Bool
    let sensorDays: Double?
    let allowCalibrations: Bool
    let appURL: URL?
    let glucoseUploadSupported: Bool
}

struct CgmDisplayStatus: Equatable, Sendable {
    let statusHighlight: String?
    let sessionStartDate: Date?
    let shouldUploadGlucose: Bool
}
