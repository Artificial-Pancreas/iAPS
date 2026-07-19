import Foundation

struct InsulinStatistics {
    let minutesWithNegativeIOB: Int
    let tddChange: Decimal
    let tddAverage: Decimal
    let tddYesterday: Decimal
    let tdd2DaysAgo: Decimal
    let tdd3DaysAgo: Decimal
    let tddActualAverage: Decimal
}

extension InsulinStatistics {
    static let empty = InsulinStatistics(
        minutesWithNegativeIOB: 0,
        tddChange: 0,
        tddAverage: 0,
        tddYesterday: 0,
        tdd2DaysAgo: 0,
        tdd3DaysAgo: 0,
        tddActualAverage: 0
    )
}
