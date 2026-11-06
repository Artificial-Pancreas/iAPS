import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Readings entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct ReadingsSnapshot: Sendable {
    let id: String?
    let date: Date?
    let direction: String?
    let glucose: Int16
    /// sgv (CGM), Manual, mbg (a meter reading from Nightscout); nil: CGM, stored before the type was
    let type: String?
}

extension ReadingsSnapshot {
    static func create(from readings: Readings) -> ReadingsSnapshot {
        ReadingsSnapshot(
            id: readings.id,
            date: readings.date,
            direction: readings.direction,
            glucose: readings.glucose,
            type: readings.type
        )
    }
}
