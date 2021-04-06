enum Bolus {
    enum Config {}
}

protocol BolusProvider: Provider {
    var suggestion: Suggestion? { get }
}
