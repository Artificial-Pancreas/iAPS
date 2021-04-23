import AuthenticationServices
import Combine
import Swinject

protocol AuthorizationManager {
    var isAuthorized: Bool { get }
    var authorizationPublisher: AnyPublisher<Bool, Never> { get }
    func authorize(credentials: Credentials) -> AnyPublisher<Void, Never>
    func logout()
}

final class BaseAuthorizationManager: AuthorizationManager, Injectable {
    private let isAuthorizedSubject = CurrentValueSubject<Bool, Never>(false)

    var authorizationPublisher: AnyPublisher<Bool, Never> { isAuthorizedSubject.eraseToAnyPublisher() }
    var isAuthorized: Bool { isAuthorizedSubject.value }

    let credentials = CurrentValueSubject<Credentials?, Never>(nil)

    private var lifetime = Lifetime()

    @Injected() private var keychain: Keychain!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func authorize(credentials: Credentials) -> AnyPublisher<Void, Never> {
        isAuthorizedSubject.send(true)
        self.credentials.send(credentials)
        return Just(()).eraseToAnyPublisher()
    }

    func logout() {
        keychain.removeObject(forKey: Login.Config.credentialsKey).publisher
            .sink(
                receiveCompletion: { _ in
                    self.isAuthorizedSubject.send(false)
                    self.credentials.send(nil)
                },
                receiveValue: {}
            )
            .store(in: &lifetime)
    }
}
