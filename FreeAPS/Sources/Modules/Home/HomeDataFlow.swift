import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow() async
    func smoothedGlucose(hours: Int) async -> [BloodGlucose]
    func carbs(hours: Int) -> [CarbsEntry]
    func announcement(_ hours: Int) async -> [Announcement]
//    func overrides() async -> [OverrideSnapshot]
}
