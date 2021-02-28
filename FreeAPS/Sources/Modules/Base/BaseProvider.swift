import Combine
import Foundation
import Swinject

protocol Provider {
    init(resolver: Resolver)
    var user: CurrentValueSubject<User?, Never> { get }
}

class BaseProvider: Provider, Injectable {
    let user = CurrentValueSubject<User?, Never>(nil)
    var lifetime = Set<AnyCancellable>()
    @Injected() var authorizationManager: AuthorizationManager!

    required init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        authorizationManager.credentials
            .map { credentials -> User? in
                guard let credentials = credentials else { return nil }
                return User(id: credentials.id)
            }
            .sink { user in
                self.user.send(user)
            }
            .store(in: &lifetime)
    }

    func type(for file: String) -> JSON.Type {
        switch file {
        case OpenAPS.Monitor.pumpHistory:
            return [PumpHistoryEvent].self
        default:
            return RawJSON.self
        }
    }
}
