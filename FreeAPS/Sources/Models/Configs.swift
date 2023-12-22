import Foundation
import SwiftUI

struct DateFilter {
    var twoHours = Date().addingTimeInterval(-2.hours.timeInterval) as NSDate
    var today = Calendar.current.startOfDay(for: Date()) as NSDate
    var day = Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
    var week = Date().addingTimeInterval(-7.days.timeInterval) as NSDate
    var month = Date().addingTimeInterval(-30.days.timeInterval) as NSDate
    var total = Date().addingTimeInterval(-90.days.timeInterval) as NSDate
}

public enum IAPSconfig {
    static let padding: CGFloat = 60
    static let iconSize: CGFloat = 20
    static let backgroundOpacity: Double = 0.1
    static let buttonSize: CGFloat = 26
    static let shadowOpacity: CGFloat = 0.75
    static let glassShadowOpacity: CGFloat = 0.6
    static let shadowFraction: CGFloat = 2
}

extension Font {
    static let buttonFont = Font.custom("TimeButtonFont", fixedSize: 14) // Same as Eventual BG size
    static let loopFont = Font.custom("LoopFont", fixedSize: 18) // Loop min ago
    static let statusFont = Font.custom("StatusFont", fixedSize: 16) // IOB, COB etc.
    static let pumpFont = Font.custom("StatusFont", fixedSize: 15)
    static let previewSmall = Font.custom("PreviewSmallFont", fixedSize: 12)
    static let previewNormal = Font.custom("PreviewNormalFont", fixedSize: 18)
    static let previewHeadline = Font.custom("PreviewHeadlineFont", fixedSize: 20)
    static let extraSmall = Font.custom("ExtraSmallFont", fixedSize: 14)

    static let suggestionHeadline = Font.custom("SuggestionHeadlineFont", fixedSize: 20)
    static let suggestionError = Font.custom("SuggestionErrorFone", fixedSize: 18)
    static let suggestionParts = Font.custom("SuggestionPartsFont", fixedSize: 17)
    static let suggestionSmallParts = Font.custom("SuggestionSmallPartsFont", fixedSize: 16)

    static let glucoseFont = Font.custom("SuggestionSmallPartsFont", fixedSize: 45)
    static let glucoseSmallFont = Font.custom("SuggestionSmallPartsFont", fixedSize: 24)
    static let bolusProgressStopFont = Font.custom("BolusProgressStop", fixedSize: 24)
    static let bolusProgressFont = Font.custom("BolusProgress", fixedSize: 20)
}
