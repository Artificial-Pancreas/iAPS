import Combine

extension Main {
    final class Provider: BaseProvider, MainProvider {
        @Injected() var authorizationManager: AuthorizationManager!
    }
}
