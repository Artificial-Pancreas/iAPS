enum Bolus {
    enum Config {}
}

protocol BolusProvider: Provider {
    var suggestion: Suggestion? { get }

    func pumpSettings() -> PumpSettings
    func fetchGlucose() -> [Readings]
    func pumpHistory() -> [PumpHistoryEvent]
}
