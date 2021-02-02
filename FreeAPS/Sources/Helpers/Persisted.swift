import Foundation

/// Attention! Do not use this wrapper for mutating structure with `didSet` handler into property owner!
/// `didSet` will never called if structure mutate into itself (by "mutating functions").
@propertyWrapper
struct Persisted<Value: Codable> {
    var wrappedValue: Value? {
        set { storage.setValue(newValue, forKey: key) }
        get { storage.getValue(Value.self, forKey: key) }
    }

    private let key: String
    private let storage: KeyValueStorage

    init(key: String, storage: KeyValueStorage = UserDefaults.standard) {
        self.storage = storage
        self.key = key
    }
}
