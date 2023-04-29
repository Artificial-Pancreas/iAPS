import Foundation

class GroupedGlucose {
    var low: Int16
    var high: Int16
    var inRange: Int16
    var date: Date

    init(low: Int16, high: Int16, inRange: Int16, date: Date) {
        self.low = low
        self.high = high
        self.inRange = inRange
        self.date = date
    }
}
