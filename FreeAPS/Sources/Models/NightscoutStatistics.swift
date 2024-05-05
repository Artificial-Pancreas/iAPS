import Foundation

struct NightscoutStatistics: JSON {
    let report = "statistics"
    let dailystats: Statistics?
    let justVersion: BareMinimum?
}
