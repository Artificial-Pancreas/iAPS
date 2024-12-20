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
        let readings: ValueSeries
        let predictions: ActivityPredictions?
        let showChart: Bool
        let showPredictions: Bool
        let chartLowThreshold: Int16?
        let chartHighThreshold: Int16?
        let chartMaxValue: Int16?
        let eventualText: Bool
        
        func withoutPredictions() -> ContentState {
            ContentState(
                bg: self.bg,
                direction: self.direction,
                change: self.change,
                date: self.date,
                iob: self.iob,
                cob: self.cob,
                loopDate: self.loopDate,
                eventual: self.eventual,
                mmol: self.mmol,
                readings: self.readings,
                predictions: nil,
                showChart: self.showChart,
                showPredictions: self.showPredictions,
                chartLowThreshold: self.chartLowThreshold,
                chartHighThreshold: self.chartHighThreshold,
                chartMaxValue: self.chartMaxValue,
                eventualText: self.eventualText
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

    let startDate: Date
}

