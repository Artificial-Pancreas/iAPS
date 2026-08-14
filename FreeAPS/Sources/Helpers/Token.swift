import Foundation
import Swinject

protocol UserToken: Sendable {
    func getIdentifier() -> String
}

final class PersistedUserToken: UserToken {
    private let keychain: Keychain

    init(resolver: Resolver) {
        keychain = resolver.resolve(Keychain.self)!
    }

    func getIdentifier() -> String {
        guard let identifier = keychain.getValue(String.self, forKey: IAPSconfig.id), identifier.count > 1 else {
            let newIdentifier = UUID().uuidString
            keychain.setValue(newIdentifier, forKey: IAPSconfig.id)
            return newIdentifier
        }
        return identifier
    }
}

final class StaticUserToken: UserToken {
    private let identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
    }

    func getIdentifier() -> String {
        identifier
    }
}
