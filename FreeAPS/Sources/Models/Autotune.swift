import Foundation

/// Per-hour ISF schedule derived from CoreData Reasons entries using the improved
/// back-calculation algorithm (isf_before = isf × ratio, global p5/p95 trim, 21-day window).
struct ReasonsISFSchedule: JSON {
    /// Per-hour median ISF in mg/dL. Keys are "0"–"23".
    let hours: [String: Double]
    /// Data-point count used for each hour's median. 0 = interpolated from neighbour.
    let counts: [String: Int]
    /// Overall median across all directly-measured hours, in mg/dL.
    let overallMedian: Double
    /// When this schedule was last computed.
    let generatedAt: Date
    /// Number of calendar days of Reasons data that contributed.
    let daysAnalyzed: Int
    /// Total Reasons entries before trimming.
    let totalEntries: Int
    /// Entries remaining after global p5/p95 trim.
    let qualifyingEntries: Int
    /// Earliest Reasons entry date included.
    let fromDate: Date
    /// Latest Reasons entry date included.
    let toDate: Date
}

struct Autotune: JSON, Equatable {
    var createdAt: Date?
    var basalProfile: [BasalProfileEntry]
    let sensitivity: Decimal
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
