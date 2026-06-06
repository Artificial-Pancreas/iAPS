import Foundation

public extension Date {
    func removingTimeInterval(_ timeInterval: TimeInterval) -> Date {
        addingTimeInterval(-timeInterval)
    }
}
