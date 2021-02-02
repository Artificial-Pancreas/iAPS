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
    required init(resolver: Resolver) {
        injectServices(resolver)
        makeTestUser()
    }
}

extension BaseProvider {
    func makeTestUser() {
        let user = User(
            id: UUID(),
            name: "Vasiliy",
            email: "example@mail.ru"
        )

        self.user.send(user)
    }
}
