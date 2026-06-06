import Combine
import LocalAuthentication

protocol UnlockManager {
    func unlock() async throws
}

struct UnlockError: Error {
    let error: Error?
}

final class BaseUnlockManager: UnlockManager {
    func unlock() async throws {
        let context = LAContext()
        var error: NSError?
        var defaultOn = true

        // If overridden in ConfigOverride.xcconfig or Config.xcconfig
        if let override: Bool = try? Configuration.value(for: "AUTHENTICATE") {
            defaultOn = override
        }

        guard defaultOn, context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "We need to make sure you are the owner of the device."
            ) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UnlockError(error: error))
                }
            }
        }
    }
}
