import Foundation
import Swinject

final class Token: Sendable {
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
