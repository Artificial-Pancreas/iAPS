import Foundation

/// Attention! Do not use this wrapper for mutating structure with `didSet` handler into property owner!
/// `didSet` will never called if structure mutate into itself (by "mutating functions").
@propertyWrapper struct Persisted<Value: Codable & Equatable> {
    var wrappedValue: Value {
        get { getValue() ?? initialValue }
        set { setValue(newValue) }
    }

    private func getValue() -> Value? {
        lock?.lock()
        defer { lock?.unlock() }
        return storage.getValue(Value.self, forKey: key)
    }

    private mutating func setValue(_ value: Value) {
        lock?.lock()
        defer { lock?.unlock() }
        storage.setValue(value, forKey: key)
    }

    private let key: String
    private let storage: KeyValueStorage
    private let lock: NSRecursiveLock?
    private let initialValue: Value
    var isInitialValue: Bool {
        if let value = getValue() {
            return value == initialValue
        }
        return true
    }

    init(
        wrappedValue: Value,
        key: String,
        storage: KeyValueStorage = UserDefaults.standard,
        lock: NSRecursiveLock? = nil
    ) {
        self.storage = storage
        self.key = key
        self.lock = lock
        initialValue = wrappedValue
        lock?.lock()
        defer { lock?.unlock() }
        if storage.getValue(Value.self, forKey: key) == nil {
            setValue(wrappedValue)
        }
    }
}
