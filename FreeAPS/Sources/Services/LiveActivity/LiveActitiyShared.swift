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

        init(dates: [Date], values: [Int16]) {
            self.dates = dates
            self.values = values
        }

        // custom encoding for the array of dates - store first + array of deltas
        enum CodingKeys: String, CodingKey {
            case startDate
            case dateDeltas
            case values
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            guard let firstDate = dates.first else {
                try container.encode(nil as Date?, forKey: .startDate)
                try container.encode([] as [Int], forKey: .dateDeltas)
                try container.encode(values, forKey: .values)
                return
            }

            try container.encode(firstDate, forKey: .startDate)
            let deltas = dates.map { Int($0.timeIntervalSince(firstDate)) }
            try container.encode(deltas, forKey: .dateDeltas)
            try container.encode(values, forKey: .values)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let startDate = try container.decode(Date.self, forKey: .startDate)
            let deltas = try container.decode([Int].self, forKey: .dateDeltas)
            dates = deltas.map { startDate.addingTimeInterval(TimeInterval($0)) }
            values = try container.decode([Int16].self, forKey: .values)
        }
    }

    struct InsulinActivitySeries: Codable, Hashable {
        let dates: [Date]
        let values: [Double]

        init(dates: [Date], values: [Double]) {
            self.dates = dates
            self.values = values
        }

        // custom encoding for the array of dates - store first + array of deltas, same as above
        enum CodingKeys: String, CodingKey {
            case startDate
            case dateDeltas
            case values
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            guard let firstDate = dates.first else {
                try container.encode(nil as Date?, forKey: .startDate)
                try container.encode([] as [Int], forKey: .dateDeltas)
                try container.encode(values, forKey: .values)
                return
            }

            try container.encode(firstDate, forKey: .startDate)
            let deltas = dates.map { Int($0.timeIntervalSince(firstDate)) }
            try container.encode(deltas, forKey: .dateDeltas)

            // Round to 4 decimal places
            let roundedValues = values.map { Double(round(10000 * $0) / 10000) }
            try container.encode(roundedValues, forKey: .values)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let startDate = try container.decode(Date.self, forKey: .startDate)
            let deltas = try container.decode([Int].self, forKey: .dateDeltas)
            dates = deltas.map { startDate.addingTimeInterval(TimeInterval($0)) }
            values = try container.decode([Double].self, forKey: .values)
        }
    }

    struct ActivityPredictions: Codable, Hashable {
        let iob: ValueSeries?
        let zt: ValueSeries?
        let cob: ValueSeries?
        let uam: ValueSeries?
    }

    let startDate: Date
}
