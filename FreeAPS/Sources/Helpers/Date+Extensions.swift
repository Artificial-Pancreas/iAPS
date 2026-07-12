import Foundation

public extension Date {
    func subtractingTimeInterval(_ timeInterval: TimeInterval) -> Date {
        addingTimeInterval(-timeInterval)
    }
}
