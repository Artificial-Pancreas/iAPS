import Combine
import Foundation

// func observe<P: Publisher>(
//    _ publisher: P,
//    in lifetime: inout Lifetime,
//    action: @escaping @Sendable (P.Output) -> Void
// ) where P.Output: Sendable, P.Failure == Never {
//    publisher
//        .sink { value in action(value) }
//        .store(in: &lifetime)
// }

func observe<P: Publisher>(
    _ publisher: P,
    in lifetime: inout Lifetime,
    action: @escaping @Sendable(P.Output) async -> Void
) where P.Output: Sendable, P.Failure == Never {
    publisher
        .sink { value in Task { await action(value) } }
        .store(in: &lifetime)
}

func observe(
    notification name: Notification.Name,
    in lifetime: inout Lifetime,
    _ handler: @escaping @Sendable() async -> Void
) {
    Task {
        for await _ in Foundation.NotificationCenter.default.notifications(named: name) {
            await handler()
        }
    }.store(in: &lifetime)
}

extension Publisher where Output: Sendable, Failure == Never {
    var sendableValues: AsyncStream<Output> {
        AsyncStream { continuation in
            let cancellable = sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
