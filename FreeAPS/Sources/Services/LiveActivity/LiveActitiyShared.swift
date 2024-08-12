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
    }

    let startDate: Date
}
