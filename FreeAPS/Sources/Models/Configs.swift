import Foundation
import SwiftUI

enum DateFilter: String, CaseIterable, Identifiable, Codable {
    case oneHour
    case twoHours
    case threeHours
    case today
    case day
    case twoDays
    case week
    case tenDays
    case fourteenDays
    case month
    case total
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour:
            "1 Hour"

        case .twoHours:
            "2 Hours"

        case .threeHours:
            "3 Hours"

        case .today:
            "Today"

        case .day:
            "Day"

        case .twoDays:
            "2 Days"

        case .week:
            "Week"

        case .tenDays:
            "10 Days"

        case .fourteenDays:
            "14 Days"

        case .month:
            "Month"

        case .total:
            "90 Days"

        case .all:
            "All"
        }
    }

    var startDate: NSDate {
        let now = Date()

        switch self {
        case .oneHour:
            return now.addingTimeInterval(-1.hours.timeInterval) as NSDate

        case .twoHours:
            return now.addingTimeInterval(-2.hours.timeInterval) as NSDate

        case .threeHours:
            return now.addingTimeInterval(-3.hours.timeInterval) as NSDate

        case .today:
            return Calendar.current.startOfDay(for: now) as NSDate

        case .day:
            return now.addingTimeInterval(-24.hours.timeInterval) as NSDate

        case .twoDays:
            return now.addingTimeInterval(-2.days.timeInterval) as NSDate

        case .week:
            return now.addingTimeInterval(-7.days.timeInterval) as NSDate

        case .tenDays:
            return now.addingTimeInterval(-10.days.timeInterval) as NSDate

        case .fourteenDays:
            return now.addingTimeInterval(-14.days.timeInterval) as NSDate

        case .month:
            return now.addingTimeInterval(-30.days.timeInterval) as NSDate

        case .total:
            return now.addingTimeInterval(-90.days.timeInterval) as NSDate

        case .all:
            return Date.distantPast as NSDate
        }
    }

    /// The actual interval
    static func interval(_ data: [Meals]) -> Double? {
        guard let first = data.first, let last = data.last, let new = first.actualDate,
              let old = last.actualDate else { return nil }
        return new.timeIntervalSince(old).hours / 24
    }
}

public enum IAPSconfig {
    static let padding: CGFloat = 60
    static let iconSize: CGFloat = 34
    static let backgroundOpacity: Double = 0.1
    static let buttonSize: CGFloat = 26
    static let shadowOpacity: CGFloat = 0.75
    static let glassShadowOpacity: CGFloat = 0.6
    static let shadowFraction: CGFloat = 2
    static let minimumCarbEquivalent: Decimal = 0.6
    static let id = "iAPS.identifier"
    static let version = "iAPS.version"
    static let newVersion = "iAPS.newVersion"
    static let inBolusView = "iAPS.inBolusView"
    static let statURL = URL(string: "https://submit.open-iaps.app")!
    /// Colors
    static let headerBackgroundLight = Color.gray.opacity(IAPSconfig.backgroundOpacity)
    static let headerBackgroundDark = Color(.systemGray5) // Color.header2.opacity(1)
    static let chartBackgroundLight = Color.white
    static let chartBackgroundDark = Color.black
    static let previewBackgroundLight = Color.white
    static let previewBackgroundDark = Color.black
    static let homeViewBackgroundLight = Color(.systemGray5) // Color.gray.opacity(IAPSconfig.backgroundOpacity * 2)
    static let homeViewBackgrundDark = Color(.systemGray5) // Color.header2.opacity(0.95)
    static let activityBackground = Color(.systemGray5)
    static let inRangeBackground = Color(.loopGreen)
}

extension Font {
    static let buttonFont = Font.custom("TimeButtonFont", fixedSize: 14) // Same as Eventual BG size
    static let infoSymbolFont = Font.custom("TimeButtonFont", fixedSize: 16) // Same as Eventual BG size

    static let loopFont = Font.custom("LoopFont", size: 13) // Loop min ago
    static let statusFont = Font.custom("StatusFont", size: 16) // IOB, COB etc.
    static let pumpFont = Font.custom("PumpFont", size: 16)

    static let previewSmall = Font.custom("PreviewSmallFont", size: 14)
    static let previewNormal = Font.custom("PreviewNormalFont", size: 16)
    static let previewHeadline = Font.custom("PreviewHeadlineFont", size: 18)
    static let previewExtraBig = Font.custom("PreviewHeadlineFont", size: 20)
    static let extraSmall = Font.custom("ExtraSmallFont", size: 12)

    static let suggestionHeadline = Font.custom("SuggestionHeadlineFont", fixedSize: 20)
    static let suggestionError = Font.custom("SuggestionErrorFone", fixedSize: 18)
    static let suggestionParts = Font.custom("SuggestionPartsFont", fixedSize: 17)
    static let suggestionSmallParts = Font.custom("SuggestionSmallPartsFont", fixedSize: 16)

    static let glucoseFont = Font.custom("SuggestionSmallPartsFont", size: 45)
    static let glucoseFontMdDl = Font.custom("SuggestionSmallPartsFont", size: 40)
    static let glucoseSmallFont = Font.custom("SuggestionSmallPartsFont", size: 24)
    static let glucoseDotFont = Font.custom("SuggestionSmallPartsFont", size: 13)

    static let bolusProgressStopFont = Font.custom("BolusProgressStop", fixedSize: 24)
    static let bolusProgressFont = Font.custom("BolusProgress", fixedSize: 20)
    static let bolusProgressBarFont = Font.custom("BolusProgressBarFont", fixedSize: 18)

    static let chartTimeFont = Font.custom("ChartTimeFont", fixedSize: 14)
    static let timeSettingFont = Font.custom("TimeSettingFont", fixedSize: 14)

    static let carbsDotFont = Font.custom("CarbsDotFont", fixedSize: 12)
    static let bolusDotFont = Font.custom("BolusDotFont", fixedSize: 12)
    static let announcementSymbolFont = Font.custom("AnnouncementSymbolFont", fixedSize: 14)
}
