extension Settings {
    final class Provider: BaseProvider, SettingsProvider {
        @Injected() var authorizationManager: AuthorizationManager!

        func logout() {
            authorizationManager.logout()
        }
    }
}
