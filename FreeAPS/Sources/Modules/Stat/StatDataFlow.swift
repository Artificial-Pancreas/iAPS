enum Stat {
    enum Config {}
}

protocol StatProvider: Provider {
    var dynamicVariables: DynamicVariables? { get }
    func reasons() -> [IOBData]?
}
