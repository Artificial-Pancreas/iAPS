extension AddCarbs {
    final class Provider: BaseProvider, AddCarbsProvider {
        var suggestion: Suggestion? {
            storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        }
    }
}
