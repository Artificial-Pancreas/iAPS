extension Bolus {
    final class Provider: BaseProvider, BolusProvider {
        var suggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }
    }
}
