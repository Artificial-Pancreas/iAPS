import Swinject

extension Bolus {
    final class Builder: BaseModuleBuilder<RootView, ViewModel<Provider>, Provider> {
        private let waitForSuggestion: Bool
        init(resolver: Resolver, waitForSuggestion: Bool) {
            self.waitForSuggestion = waitForSuggestion
            super.init(resolver: resolver)
        }

        override func buildViewModel() -> Bolus.ViewModel<Bolus.Provider> {
            ViewModel(provider: Provider(resolver: resolver), resolver: resolver, waitForSuggestion: waitForSuggestion)
        }
    }
}
