import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    func heartbeatNow() async
    func filteredGlucose(hours: Int) async -> [BloodGlucose]
    func pumpHistory(hours: Int) async -> [PumpHistoryEvent]
    func autotunedBasalProfile() async -> [BasalProfileEntry]
    func basalProfile() async -> [BasalProfileEntry]
    func tempTargets(hours: Int) async -> [TempTarget]
    func carbs(hours: Int) async -> [CarbsEntry]
    func tempTarget() async -> TempTarget?
    func announcement(_ hours: Int) async -> [Announcement]
    func overrides() async -> [Override]
}
