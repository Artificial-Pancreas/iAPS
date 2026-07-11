import Foundation
import SwiftDate

struct TempTarget: JSON, Identifiable, Equatable, Hashable {
    var id = UUID().uuidString
    let name: String?
    var createdAt: Date
    let targetTop: Decimal?
    let targetBottom: Decimal?
    let duration: Decimal
    let enteredBy: String?
    let reason: String?

    static let manual = "iAPS"
    static let custom = "Temp target"
    static let cancel = "Cancel"

    var displayName: String {
        name ?? reason ?? TempTarget.custom
    }

    static func == (lhs: TempTarget, rhs: TempTarget) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }

    static func cancel(at date: Date) -> TempTarget {
        TempTarget(
            name: TempTarget.cancel,
            createdAt: date,
            targetTop: 0,
            targetBottom: 0,
            duration: 0,
            enteredBy: TempTarget.manual,
            reason: TempTarget.cancel
        )
    }
}

extension TempTarget {
    var endDate: Date {
        createdAt.addingTimeInterval(Int(duration).minutes.timeInterval)
    }

    /// a cancel record (duration == 0) is never active
    func isActive(at date: Date) -> Bool {
        duration != 0 && createdAt <= date && date < endDate
    }
}

extension TempTarget {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case createdAt = "created_at"
        case targetTop
        case targetBottom
        case duration
        case enteredBy
        case reason
    }
}
