import Foundation

struct NightscoutStatistics: JSON {
    var report = "statistics"
    let dailystats: Statistics?
    let justVersion: BareMinimum?
}
