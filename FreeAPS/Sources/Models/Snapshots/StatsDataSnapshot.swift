import CoreData
import Foundation

// a snapshot (DTO) of a CoreData StatsData entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct StatsDataSnapshot: Sendable {
    let lastrun: Date?
}

extension StatsDataSnapshot {
    static func create(from stats: StatsData) -> StatsDataSnapshot {
        StatsDataSnapshot(
            lastrun: stats.lastrun,
        )
    }
}
