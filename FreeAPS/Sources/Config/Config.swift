import Foundation
import SwiftDate

enum Config {
    static let treatWarningsAsErrors = true
    static let withSignPosts = true
    static let loopIntervalFiveMinutes: TimeInterval = .seconds(270) // 4.5 minutes
    static let loopIntervalOneMinute: TimeInterval = .seconds(50)
    static let eхpirationInterval: TimeInterval = .minutes(10)
}
