import Foundation

enum Home {
    enum Config {}
}

protocol HomeProvider: Provider {
    var suggestion: Suggestion? { get }
    func fetchAndLoop()
    func filteredGlucose(hours: Int) -> [BloodGlucose]
    func pumpHistory(hours: Int) -> [PumpHistoryEvent]
}
