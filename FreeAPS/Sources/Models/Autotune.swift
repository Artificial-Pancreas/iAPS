import Foundation

/// A per-hour median ISF schedule derived from CoreData Reasons entries.
///
/// Built by `OpenAPS.buildReasonsISFSchedule()` when autotune runs with a dynamic algorithm
/// (AutoISF or Dynamic ISF). All ISF values are stored in **mg/dL** regardless of the user's
/// display-unit preference; callers must convert for display.
struct ReasonsISFSchedule: JSON {
    /// Per-hour median ISF in mg/dL. Keys are "0" – "23" (hour of day).
    let hours: [String: Double]
    /// Number of qualifying Reasons entries used to compute each hour's median.
    /// A count of 0 means the hour had insufficient data and was interpolated from its neighbours.
    let counts: [String: Int]
    /// Overall median across all directly-measured hours, in mg/dL.
    let overallMedian: Double
    /// When this schedule was computed.
    let generatedAt: Date
}

struct Autotune: JSON, Equatable {
    var createdAt: Date?
    var basalProfile: [BasalProfileEntry]
    var sensitivity: Decimal
    let carbRatio: Decimal
}

extension Autotune {
    private enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case basalProfile = "basalprofile"
        case sensitivity = "sens"
        case carbRatio = "carb_ratio"
    }
}
