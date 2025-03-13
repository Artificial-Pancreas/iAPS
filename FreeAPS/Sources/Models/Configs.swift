import Foundation
import SwiftUI

struct DateFilter {
    var twoHours = Date().addingTimeInterval(-2.hours.timeInterval) as NSDate
    var threeHours = Date().addingTimeInterval(-3.hours.timeInterval) as NSDate
    var today = Calendar.current.startOfDay(for: Date()) as NSDate
    var day = Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
    var twoDays = Date().addingTimeInterval(-2.days.timeInterval) as NSDate
    var week = Date().addingTimeInterval(-7.days.timeInterval) as NSDate
    var month = Date().addingTimeInterval(-30.days.timeInterval) as NSDate
    var total = Date().addingTimeInterval(-90.days.timeInterval) as NSDate
    var tenDays = Date().addingTimeInterval(-10.days.timeInterval) as NSDate
    var fourteen = Date().addingTimeInterval(-14.days.timeInterval) as NSDate
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

    static let bolusProgressStopFont = Font.custom("BolusProgressStop", fixedSize: 24)
    static let bolusProgressFont = Font.custom("BolusProgress", fixedSize: 20)
    static let bolusProgressBarFont = Font.custom("BolusProgressBarFont", fixedSize: 18)

    static let chartTimeFont = Font.custom("ChartTimeFont", fixedSize: 14)
    static let timeSettingFont = Font.custom("TimeSettingFont", fixedSize: 14)

    static let carbsDotFont = Font.custom("CarbsDotFont", fixedSize: 12)
    static let bolusDotFont = Font.custom("BolusDotFont", fixedSize: 12)
    static let announcementSymbolFont = Font.custom("AnnouncementSymbolFont", fixedSize: 14)
}
