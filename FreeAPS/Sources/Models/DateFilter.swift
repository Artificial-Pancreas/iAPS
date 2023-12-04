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
    static let iconSize: CGFloat = 18
}

extension Font {
    static let buttonFont = Font.custom("TimeButtonFont", fixedSize: 14) // Same as Eventual BG size
    static let loopFont = Font.custom("LoopFont", fixedSize: 18) // Loop min ago
    static let statusFont = Font.custom("StatusFont", fixedSize: 18) // IOB, COB etc.
    static let previewSmall = Font.custom("PreviewSmallFont", fixedSize: 10)
    static let previewNormal = Font.custom("PreviewNormalFont", fixedSize: 18)
    static let previewHeadline = Font.custom("PreviewHeadlineFont", fixedSize: 20)
    static let extraSmall = Font.custom("ExtraSmallFont", fixedSize: 14)

    static let suggestionHeadline = Font.custom("SuggestionHeadlineFont", fixedSize: 20)
    static let suggestionError = Font.custom("SuggestionErrorFone", fixedSize: 18)
    static let suggestionParts = Font.custom("SuggestionPartsFont", fixedSize: 20)
    static let suggestionSmallParts = Font.custom("SuggestionSmallPartsFont", fixedSize: 16)
}

extension AngularGradient {
    static let angularGradientIAPS = AngularGradient(colors: [
        Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
        Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
        Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
        Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902),
        Color(red: 0.7215686275, green: 0.3411764706, blue: 1)
    ], center: .center, startAngle: .degrees(270), endAngle: .degrees(-90))
}
