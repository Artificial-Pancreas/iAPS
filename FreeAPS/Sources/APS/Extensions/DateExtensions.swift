import Foundation

extension Date {
    var truncatedToSecond: Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.down))
    }
}
