extension Settings {
    final class Provider: BaseProvider, SettingsProvider {
        func logout() {
            authorizationManager.logout()
        }
    }
}
