import AuthenticationServices
import Combine
import Swinject

protocol AuthorizationManager {
    var isAuthorized: Bool { get }
    var authorizationPublisher: AnyPublisher<Bool, Never> { get }
    func authorize(credentials: ASAuthorizationAppleIDCredential) -> AnyPublisher<Void, Never>
    func logout()
}

final class BaseAuthorizationManager: AuthorizationManager, Injectable {
    private let isAuthorizedSubject = CurrentValueSubject<Bool, Never>(false)

    var authorizationPublisher: AnyPublisher<Bool, Never> { isAuthorizedSubject.eraseToAnyPublisher() }
    var isAuthorized: Bool { isAuthorizedSubject.value }

    private var lifetime = Set<AnyCancellable>()

    @Injected() private var keychain: Keychain!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func authorize(credentials _: ASAuthorizationAppleIDCredential) -> AnyPublisher<Void, Never> {
        isAuthorizedSubject.send(true)
        // TODO: send data to server
        return Just(()).eraseToAnyPublisher()
    }

    func logout() {
        keychain.removeObject(forKey: Login.Config.credentialsKey).publisher
            .sink(
                receiveCompletion: { _ in
                    self.isAuthorizedSubject.send(false)
                },
                receiveValue: {}
            )
            .store(in: &lifetime)
    }
}
