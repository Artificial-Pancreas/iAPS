import SwiftUI

enum Main {
    enum Config {}

    struct Modal: Identifiable {
        let screen: Screen
        let view: AnyView

        var id: Int { screen.id }
    }

    enum Scene {
        case authorized
        case onboarding

        var screen: Screen {
            switch self {
            case .authorized:
                return .authorizedRoot
            case .onboarding:
                return .onboarding
            }
        }
    }
}

protocol MainProvider: Provider {
    var authorizationManager: AuthorizationManager! { get }
}
