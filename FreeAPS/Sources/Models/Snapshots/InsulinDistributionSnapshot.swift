import CoreData
import Foundation

// a snapshot (DTO) of a CoreData InsulinDistribution entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct InsulinDistributionSnapshot: Sendable {
    let date: Date?
    let bolus: Decimal?
    let scheduledBasal: Decimal?
    let tempBasal: Decimal?
}

extension InsulinDistributionSnapshot {
    static func create(from record: InsulinDistribution) -> InsulinDistributionSnapshot {
        InsulinDistributionSnapshot(
            date: record.date,
            bolus: record.bolus?.decimalValue,
            scheduledBasal: record.scheduledBasal?.decimalValue,
            tempBasal: record.tempBasal?.decimalValue,
        )
    }
}
