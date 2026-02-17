
import Foundation

enum MealsRange: String, CaseIterable, Identifiable {
    case oneWeek = "1 week"
    case twoWeeks = "2 weeks"
    case threeWeeks = "3 weeks"
    case oneMonth = "1 month"
    case twoMonths = "2 months"
    case threeMonths = "3 months"

    var id: String { rawValue }

    var days: Int {
        switch self {
        case .oneWeek: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .oneMonth: return 28
        case .twoMonths: return 60
        case .threeMonths: return 90
        }
    }
}
