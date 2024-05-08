import Foundation

enum FontTracking: String, JSON, Identifiable, CaseIterable, Codable {
    var id: String { rawValue }

    case tighter
    case tight
    case normal
    case wide

    var displayName: String {
        switch self {
        case .tighter:
            NSLocalizedString("Tighter", comment: "")
        case .tight:
            NSLocalizedString("Tight", comment: "")
        case .normal:
            NSLocalizedString("Normal", comment: "")
        case .wide:
            NSLocalizedString("Wide", comment: "")
        }
    }

    var value: Double {
        switch self {
        case .tighter: -0.07
        case .tight: -0.04
        case .normal: 0
        case .wide: 0.04
        }
    }
}
