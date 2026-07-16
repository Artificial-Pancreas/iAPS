import Combine
import Foundation

protocol LifetimeOwner: AnyObject, Sendable {
    var lifetime: CancelBag { get }
}

// a Sendable replacement for the raw Lifetime=Set<AnyCancellable>
// @unchecked because, even though the class is mutable, we guarantee safety by using the lock
// TODO: consider Swift 6 `Mutex<Set<AnyCancellable>>` to drop `@unchecked Sendable` and the manual NSLock
final class CancelBag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellables: Set<AnyCancellable> = []
    func store(_ c: AnyCancellable) { _ = lock.withLock { cancellables.insert(c) } }
    func cancelAll() {
        let drained = lock.withLock { defer { cancellables.removeAll() }
            return cancellables }
        drained.forEach { $0.cancel() }
    }

    // deinit: the Set deallocs → each AnyCancellable cancels automatically (same teardown as today)
}

extension Task {
    // can be used as Task { ... }.store(in: lifetime) where lifetime: CancelBag
    func store(in bag: CancelBag) {
        bag.store(AnyCancellable(cancel))
    }
}

extension Cancellable {
    func store(in bag: CancelBag) { bag.store(AnyCancellable(self)) }
}

extension Publisher where Output: Sendable, Failure == Never {
    func sendableValues(
        bufferingPolicy: AsyncStream<Output>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Output> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let cancellable = sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }

    var sendableValues: AsyncStream<Output> {
        sendableValues()
    }
}

// These helpers hold `object` weakly and feed every emission through a single
// serial `for await` loop (one task per subscription).
//
// Why `on object:` is required: a closure that mentions `self` captures it
// strongly at the call site, before `observe` can do anything about it. By
// passing the object in and handing it back as a parameter, the callback never
// captures `self`, so there is no retain cycle and emissions stay ordered.
//
// Usage:
//   observe(somePublisher, on: self) { me, value in
//       await me.handle(value)
//   }
//   observe(someStream.debounce(for: .seconds(1)), on: self) { me, value in
//       await me.handle(value)
//   }

func _observe<S: AsyncSequence & Sendable, Object: LifetimeOwner>(
    _ sequence: S,
    on object: Object,
    action: @escaping @Sendable(Object, S.Element) async -> Void
) where S.Element: Sendable { // TODO: when we move the target to iOS18+ - add  `S.Failure == Never` and remove the try below
    let bag = object.lifetime
    Task { [weak object] in
        do {
            for try await element in sequence {
                guard let object else { break }
                await action(object, element)
            }
        } catch {}
    }.store(in: bag)
}

// Convenience: bridge a Combine publisher into the AsyncSequence overload above.
func _observe<Output: Sendable, Object: LifetimeOwner>(
    _ publisher: some Publisher<Output, Never>,
    on object: Object,
    bufferingPolicy: AsyncStream<Output>.Continuation.BufferingPolicy = .unbounded,
    action: @escaping @Sendable(Object, Output) async -> Void
) {
    _observe(publisher.sendableValues(bufferingPolicy: bufferingPolicy), on: object, action: action)
}

func _observe<Object: LifetimeOwner>(
    notification name: Notification.Name,
    on object: Object,
    _ handler: @escaping @Sendable(Object) async -> Void
) {
    let bag = object.lifetime
    Task { [weak object] in
        for await _ in Foundation.NotificationCenter.default.notifications(named: name) {
            guard let object else { break }
            await handler(object)
        }
    }.store(in: bag)
}

extension LifetimeOwner {
    func observe<S: AsyncSequence & Sendable>(
        _ sequence: S,
        perform action: @escaping @Sendable(Self, S.Element) async -> Void
    ) where S.Element: Sendable { // TODO: when we move the target to iOS18+ - add  `S.Failure == Never`
        _observe(sequence, on: self, action: action)
    }

    func observe<Output: Sendable>(
        _ publisher: some Publisher<Output, Never>,
        bufferingPolicy: AsyncStream<Output>.Continuation.BufferingPolicy = .unbounded,
        perform action: @escaping @Sendable(Self, Output) async -> Void
    ) {
        _observe(publisher, on: self, bufferingPolicy: bufferingPolicy, action: action)
    }

    func observe(
        notification name: Notification.Name,
        perform handler: @escaping @Sendable(Self) async -> Void
    ) {
        _observe(notification: name, on: self, handler)
    }
}
