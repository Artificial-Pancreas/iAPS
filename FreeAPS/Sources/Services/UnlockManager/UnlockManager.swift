import Combine
import LocalAuthentication

protocol UnlockManager {
    func unlock() -> AnyPublisher<Void, Error>
}

struct UnlockError: Error {
    let error: Error?
}

final class BaseUnlockManager: UnlockManager {
    func unlock() -> AnyPublisher<Void, Error> {
        Future { promise in
            let context = LAContext()
            var error: NSError?
            var defaultOn = true

            let handler: (Bool, Error?) -> Void = { success, error in
                if success {
                    promise(.success(()))
                } else {
                    promise(.failure(UnlockError(error: error)))
                }
            }

            let reason = "We need to make sure you are the owner of the device."

            // If overridden in ConfigOverride.xcconfig or Config.xcconfig
            if let override: Bool = try? Configuration.value(for: "AUTHENTICATE") {
                defaultOn = override
            }

            if defaultOn, context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: reason,
                    reply: handler
                )
            } else {
                handler(true, nil)
            }
        }
        .eraseToAnyPublisher()
    }
}
