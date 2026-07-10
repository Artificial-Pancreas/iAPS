import Combine
import UIKit

// MARK: - UI-only subscriptions that exist only while the app is in the foreground

@MainActor
final class UIBindings {
    private var recipes: [() -> AnyCancellable] = []
    private var active: [AnyCancellable] = []
    private var isActive: Bool
    private var lifecycle = Set<AnyCancellable>()

    init() {
        isActive = UIApplication.shared.applicationState != .background
        Foundation.NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.deactivate() } }
            .store(in: &lifecycle)
        Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.activate() } }
            .store(in: &lifecycle)
    }

    func add(_ make: @escaping () -> AnyCancellable) {
        recipes.append(make)
        if isActive {
            active.append(make())
        }
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        active.removeAll()
    }

    private func activate() {
        guard !isActive else { return }
        isActive = true
        active = recipes.map { $0() }
    }
}

@MainActor protocol UIBindingOwner: AnyObject, Sendable {
    var uiBindings: UIBindings { get }
}

/// holds the last value that was delivered
private final class DeliveredValueBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func replaceIfNew(_ new: Value, isDuplicate: (Value, Value) -> Bool) -> Bool {
        lock.withLock {
            if let value, isDuplicate(value, new) { return false }
            value = new
            return true
        }
    }
}

@MainActor private func _observeUI<Root: Sendable, Value: Sendable, Object: UIBindingOwner>(
    _ subject: CurrentValueSubject<Root, Never>,
    map transform: @escaping @Sendable(Root) -> Value,
    isDuplicate: @escaping @Sendable(Value, Value) -> Bool,
    dropInitial: Bool,
    on object: Object,
    perform action: @escaping @MainActor @Sendable(Object, Value) async -> Void
) {
    let delivered = DeliveredValueBox<Value>()
    if dropInitial {
        _ = delivered.replaceIfNew(transform(subject.value), isDuplicate: isDuplicate)
    }
    object.uiBindings.add { [weak object] in
        let stream = subject.map(transform).sendableValues
        let task = Task { [weak object] in
            for await value in stream {
                guard let object else { break }
                guard delivered.replaceIfNew(value, isDuplicate: isDuplicate) else { continue }
                await action(object, value)
            }
        }
        return AnyCancellable(task.cancel)
    }
}

// These are for subscriptions whose only purpose is updating what is rendered on screen
// they stop existing while the app is backgrounded.
// When the observed value is `Equatable` it is also deduplicated.
//
// `dropInitial: true` treats the subject's current value as already delivered: the handler
// first fires when the value changes (use it when `subscribe()` does the initial setup
// explicitly, like `.dropFirst()` did on a plain `observe`).
extension UIBindingOwner {
    func observeUI<Value: Equatable & Sendable>(
        _ subject: CurrentValueSubject<Value, Never>,
        dropInitial: Bool = false,
        perform action: @escaping @MainActor @Sendable(Self, Value) async -> Void
    ) {
        _observeUI(subject, map: { $0 }, isDuplicate: { $0 == $1 }, dropInitial: dropInitial, on: self, perform: action)
    }

    func observeUI<Value: Sendable>(
        _ subject: CurrentValueSubject<Value, Never>,
        perform action: @escaping @MainActor @Sendable(Self, Value) async -> Void
    ) {
        _observeUI(subject, map: { $0 }, isDuplicate: { _, _ in false }, dropInitial: false, on: self, perform: action)
    }

    func observeUI<Root: Sendable, Value: Equatable & Sendable>(
        _ subject: CurrentValueSubject<Root, Never>,
        map transform: @escaping @Sendable(Root) -> Value,
        dropInitial: Bool = false,
        perform action: @escaping @MainActor @Sendable(Self, Value) async -> Void
    ) {
        _observeUI(subject, map: transform, isDuplicate: { $0 == $1 }, dropInitial: dropInitial, on: self, perform: action)
    }
}
