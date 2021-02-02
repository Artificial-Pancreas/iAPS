enum Onboarding {
    enum Config {}

    enum Stage {
        case login
        case requestPermissions

        var screen: Screen {
            switch self {
            case .login:
                return .login
            case .requestPermissions:
                return .requestPermissions
            }
        }
    }
}

protocol OnboardingProvider: Provider {}
