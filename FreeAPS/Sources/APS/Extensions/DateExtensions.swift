import Foundation

extension Date {
    var truncatedToSecond: Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded(.down))
    }

    /// in JSON files - dates are stored as ISO-8601 with millisecond precision
    /// in-memory Dates keep full precision, so we cannot == them
    func isSameInstant(as other: Date) -> Bool {
        abs(timeIntervalSince(other)) < 0.001
    }
}
