extension AuthotizedRoot {
    final class Provider: BaseProvider, AuthotizedRootProvider {
        @Injected() var authorizationManager: AuthorizationManager!
    }
}
