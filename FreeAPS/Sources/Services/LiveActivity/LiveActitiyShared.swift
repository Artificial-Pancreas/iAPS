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
        let chartLayout: ActivityChartLayout
        let chartLowThreshold: Int16?
        let chartHighThreshold: Int16?
        let chartMaxValue: Int16?
        let eventualText: Bool
        let smallStatus: Bool

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
                chartLayout: chartLayout,
                chartLowThreshold: chartLowThreshold,
                chartHighThreshold: chartHighThreshold,
                chartMaxValue: chartMaxValue,
                eventualText: eventualText,
                smallStatus: smallStatus
            )
        }
    }

    struct ValueSeries: Codable, Hashable {
        let dates: [Date]
        let values: [Int16]
    }

    struct ContentStateReading: Codable, Hashable {
        let date: Date
        let glucose: Int16
    }

    struct ActivityPredictions: Codable, Hashable {
        let iob: ValueSeries?
        let zt: ValueSeries?
        let cob: ValueSeries?
        let uam: ValueSeries?
    }

    enum ActivityChartLayout: String, CaseIterable, Identifiable, Codable {
        var id: String { rawValue }
        case EventualAtTheTop
        case EventualAtTheBottom
        case EventualOnTheRight
        case EventualOnTheRightWithTime
        case NoEventual
    }

    let startDate: Date
}
