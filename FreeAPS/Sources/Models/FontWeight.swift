import Foundation

enum FontWeight: String, JSON, Identifiable, CaseIterable, Codable {
    var id: String { rawValue }

    case light
    case regular
    case medium
    case semibold
    case bold
    case black

    var displayName: String {
        switch self {
        case .light:
            return NSLocalizedString("Light", comment: "")
        case .regular:
            return NSLocalizedString("Regular", comment: "")
        case .medium:
            return NSLocalizedString("Medium", comment: "")
        case .semibold:
            return NSLocalizedString("Semibold", comment: "")
        case .bold:
            return NSLocalizedString("Bold", comment: "")
        case .black:
            return NSLocalizedString("Black", comment: "")
        }
    }
}
