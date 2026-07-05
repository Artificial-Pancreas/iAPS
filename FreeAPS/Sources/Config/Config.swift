import Foundation
import SwiftDate

enum Config {
    static let treatWarningsAsErrors = true
    static let withSignPosts = true
    static let loopIntervalFiveMinutes = 270.seconds.timeInterval // 4.5 minutes
    static let loopIntervalOneMinute = 50.seconds.timeInterval
    static let eхpirationInterval = 10.minutes.timeInterval
}
