import Foundation

struct NigtscoutExercise: JSON, Hashable, Equatable {
    var duration: Int?
    var eventType: EventType
    var createdAt: Date
    var enteredBy: String?
    var notes: String?
    // var mills: Int

    static let local = "iAPS"

    static let empty = NigtscoutExercise(from: "{}")!

    static func == (lhs: NigtscoutExercise, rhs: NigtscoutExercise) -> Bool {
        (lhs.createdAt) == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }
}

extension NigtscoutExercise {
    private enum CodingKeys: String, CodingKey {
        case duration
        case eventType
        case createdAt = "created_at"
        case enteredBy
        case notes
        // case mills
    }
}
