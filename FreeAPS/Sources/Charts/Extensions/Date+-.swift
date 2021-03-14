import Foundation

extension Date {
    static func - (lhs: Date, rhs: Date) -> Double {
        lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
}
