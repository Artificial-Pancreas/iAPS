import AuthenticationServices

extension Login {
    final class Provider: BaseProvider, LoginProvider {
        @Injected() var authorizationManager: AuthorizationManager!
        @Injected() private var keychain: Keychain!

        func authorize(credentials: Credentials) {
            authorizationManager.authorize(credentials: credentials)
                .sink { _ in
                    self.keychain.setValue(credentials, forKey: Config.credentialsKey)
                }
                .store(in: &lifetime)
        }

        var credentials: Credentials? {
            keychain.getValue(Credentials.self, forKey: Config.credentialsKey)
        }
    }
}
