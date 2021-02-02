import SwiftUI
import Swinject

extension Onboarding {
    class ViewModel<Provider>: BaseViewModel<Provider>, ObservableObject where Provider: OnboardingProvider {
        @Published var stage: Stage

        required init(provider: Provider, resolver: Resolver) {
            stage = .login
            super.init(provider: provider, resolver: resolver)
        }
    }
}
