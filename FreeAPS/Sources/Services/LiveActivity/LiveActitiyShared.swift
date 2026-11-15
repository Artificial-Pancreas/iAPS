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
        let showChart: Bool
        let watchChart: Bool
        let watchPredictions: Bool
        let watchDelta: Bool
        let watchEventual: Bool
        /// in range is `chartLowThreshold ... chartHighThreshold`, inclusive, mg/dL: the app sends the Statistics band
        /// edges (`StatsBands(settings:)`), so the chart colours a reading as Home does. A state encoded by an older
        /// app has the truncated low/high settings here (at most 1 mg/dL off) until its next update.
        let chartLowThreshold: Int16
        let chartHighThreshold: Int16

        enum ReadingRange: Equatable {
            case below
            case inRange
            case above
        }

        /// red below low, green in range (inclusive), orange above high
        static func readingRange(_ mgdl: Int16, low: Int16, high: Int16) -> ReadingRange {
            if mgdl < low { return .below }
            if mgdl > high { return .above }
            return .inRange
        }

        func readingRange(_ mgdl: Int16) -> ReadingRange {
            Self.readingRange(mgdl, low: chartLowThreshold, high: chartHighThreshold)
        }

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
                showChart: showChart,
                watchChart: watchChart,
                watchPredictions: watchPredictions,
                watchDelta: watchDelta,
                watchEventual: watchEventual,
                chartLowThreshold: chartLowThreshold,
                chartHighThreshold: chartHighThreshold
            )
        }
    }

    struct ValueSeries: Codable, Hashable {
        let dates: [Date]
        let values: [Int16]
    }

    struct ActivityPredictions: Codable, Hashable {
        let iob: ValueSeries?
        let zt: ValueSeries?
        let cob: ValueSeries?
        let uam: ValueSeries?
    }

    let startDate: Date
}
