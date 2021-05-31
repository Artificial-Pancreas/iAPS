import AuthenticationServices
import Combine
import Swinject

protocol AuthorizationManager {
    var authorizationPublisher: AnyPublisher<Bool, Never> { get }
    func authorize(credentials: Credentials) -> AnyPublisher<Void, Never>
    func logout()
}

final class BaseAuthorizationManager: AuthorizationManager, Injectable {
    private let isAuthorizedSubject = CurrentValueSubject<Bool?, Never>(nil)

    var authorizationPublisher: AnyPublisher<Bool, Never> { isAuthorizedSubject.ignoreNil().eraseToAnyPublisher() }

    let credentials = CurrentValueSubject<Credentials?, Never>(nil)

    private var lifetime = Lifetime()

    @Injected() private var keychain: Keychain!

    init(resolver: Resolver) {
        injectServices(resolver)
        if let creds = keychain.getValue(Credentials.self, forKey: Login.Config.credentialsKey) {
            credentials.send(creds)
            isAuthorizedSubject.send(true)
        } else {
            isAuthorizedSubject.send(false)
        }
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
