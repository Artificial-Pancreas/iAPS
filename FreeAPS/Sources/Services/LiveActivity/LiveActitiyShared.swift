import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let bg: String
        let direction: String?
        let change: String
        let date: Date
        let iob: String
        let cob: String
        let loopDate: Date
        let eventual: String
        let mmol: Bool
        let readings: ValueSeries?
        let predictions: ActivityPredictions?
        let activity: InsulinActivitySeries?
        let activity1U: Double?
        let activityMax: Double?
        let showChart: Bool
        let chartLowThreshold: Int16
        let chartHighThreshold: Int16

        func withoutPredictions() -> ContentState {
            ContentState(
                bg: bg,
                direction: direction,
                change: change,
                date: date,
                iob: iob,
                cob: cob,
                loopDate: loopDate,
                eventual: eventual,
                mmol: mmol,
                readings: readings,
                predictions: nil,
                activity: activity,
                activity1U: activity1U,
                activityMax: activityMax,
                showChart: showChart,
                chartLowThreshold: chartLowThreshold,
                chartHighThreshold: chartHighThreshold
            )
        }
    }

    struct ValueSeries: Codable, Hashable {
        let dates: [Date]
        let values: [Int16]
    }

    struct InsulinActivitySeries: Codable, Hashable {
        let dates: [Date]
        let values: [Double]
    }

    struct ActivityPredictions: Codable, Hashable {
        let iob: ValueSeries?
        let zt: ValueSeries?
        let cob: ValueSeries?
        let uam: ValueSeries?
    }

    let startDate: Date
}
