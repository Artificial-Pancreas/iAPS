import AuthenticationServices

extension Login {
    final class Provider: BaseProvider, LoginProvider {
        @Injected() var authorizationManager: AuthorizationManager!
        @Injected() private var keychain: Keychain!

        func authorize(credentials: ASAuthorizationAppleIDCredential) {
            authorizationManager.authorize(credentials: credentials)
                .sink { _ in
                    self.keychain.setValue(CredentialsWrapper(credentials), forKey: Config.credentialsKey)
                }
                .store(in: &lifetime)
        }

        var credentials: ASAuthorizationAppleIDCredential? {
            keychain.getValue(CredentialsWrapper.self, forKey: Config.credentialsKey)?.credentials
        }
    }
}
