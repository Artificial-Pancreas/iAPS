import CoreData
import Foundation

// a snapshot (DTO) of a CoreData Profiles entity
// entities are not safe to send across actor/thread boundaries (not Sendable), this snapshot is
struct ProfilesSnapshot: Sendable {
    let date: Date?
    let name: String?
    let uploaded: Bool
}

extension ProfilesSnapshot {
    static func create(from record: Profiles) -> ProfilesSnapshot {
        ProfilesSnapshot(
            date: record.date,
            name: record.name,
            uploaded: record.uploaded,
        )
    }
}
