import Foundation

enum APSDataFormatter {
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f
    }()

    private static func formatToPrecision(_ number: Double, precision: Int, minimumFraction: Int = 1) -> String {
        numberFormatter.minimumFractionDigits = minimumFraction
        numberFormatter.maximumFractionDigits = precision
        return numberFormatter.string(from: NSNumber(value: number))!
    }

    private static func formatTime(difference: Double) -> String {
        let rawHours = Int(round(difference / 3600))
        let days = rawHours / 24
        let hours = rawHours - (24 * days)
        return ("\(days)d\(hours)h")
    }

    static func format(inputValue: Double, to formatType: APSDataTypes) -> String {
        switch formatType {
        case .delta:
            let formattedDelta = formatToPrecision(inputValue, precision: 2)
            if inputValue >= 0 {
                return "+" + formattedDelta
            }
            return formattedDelta
        case .glucose:
            return formatToPrecision(inputValue, precision: 1)
        case .cob:
            return formatToPrecision(inputValue, precision: 1) + "g"
        case .iob:
            return formatToPrecision(inputValue, precision: 2) + "U"
        case .basal:
            return formatToPrecision(inputValue, precision: 2, minimumFraction: 2) + "U"
        case .time:
            return formatTime(difference: inputValue)
        }
    }
}
