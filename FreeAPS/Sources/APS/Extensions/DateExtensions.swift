import Foundation

extension Date {
    var roundedTo1Second: Date {
        let interval = timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: interval.rounded())
    }
}
