enum AddCarbs {
    enum Config {}
}

protocol AddCarbsProvider: Provider {
    var suggestion: Suggestion? { get }
}
