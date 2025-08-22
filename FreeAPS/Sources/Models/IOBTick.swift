import Foundation

// used in insulin activity chart, a subset of fields from IOBEntry that are stored in Core Data
struct IOBTick: Equatable, Comparable {
    let time: Date
    let iob: Decimal
    let activity: Decimal

    static func < (lhs: IOBTick, rhs: IOBTick) -> Bool {
        rhs.time < lhs.time
    }
}
