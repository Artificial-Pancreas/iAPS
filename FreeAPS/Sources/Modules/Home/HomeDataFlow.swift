import Foundation
import LoopKitUI

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    var suggestion: Suggestion? { get }
    var enactedSuggestion: Suggestion? { get }
    func heartbeatNow()
    func filteredGlucose(hours: Int) -> [BloodGlucose]
    func pumpHistory(hours: Int) -> [PumpHistoryEvent]
    func pumpSettings() -> PumpSettings
    func autotunedBasalProfile() -> [BasalProfileEntry]
    func basalProfile() -> [BasalProfileEntry]
    func tempTargets(hours: Int) -> [TempTarget]
    func carbs(hours: Int) -> [CarbsEntry]
    func pumpBattery() -> Battery?
    func pumpReservoir() -> Decimal?
    func tempTarget() -> TempTarget?
}
