import Foundation

@propertyWrapper public struct PersistedProperty<Value> {
    let key: String
    let storageURL: URL

    public init(key: String, shared: Bool = false) {
        self.key = key

        let documents: URL

        if shared {
            guard let appGroup = Bundle.main.appGroupSuiteName else {
                preconditionFailure(
                    "Could not get the app group suite name."
                )
            }
            guard let directoryURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
                preconditionFailure(
                    "Could not get a container directory URL. Please ensure App Groups are set up correctly in entitlements."
                )
            }
            documents = directoryURL.appendingPathComponent("com.loopkit.LoopKit", isDirectory: true)

        } else {
            guard let localDocuments = try? FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) else {
                preconditionFailure("Could not get a documents directory URL.")
            }
            documents = localDocuments
        }
        storageURL = documents.appendingPathComponent(key + ".plist")
    }

    public var wrappedValue: Value? {
        get {
            do {
                let data = try Data(contentsOf: storageURL)
                debug(.openAPS, "Reading \(key) from \(storageURL.absoluteString)")
                guard let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? Value
                else {
                    debug(.openAPS, "Unexpected type for \(key)")
                    return nil
                }
                return value
            } catch {
                debug(.openAPS, "Error reading \(key): \(error.localizedDescription)")
            }
            return nil
        }
        set {
            guard let newValue = newValue else {
                do {
                    try FileManager.default.removeItem(at: storageURL)
                } catch {
                    debug(.openAPS, "Error deleting \(key): \(error.localizedDescription)")
                }
                return
            }
            do {
                let data = try PropertyListSerialization.data(fromPropertyList: newValue, format: .binary, options: 0)
                try data.write(to: storageURL, options: .atomic)
                debug(.openAPS, "Wrote \(key) to \(storageURL.absoluteString)")
            } catch {
                debug(.openAPS, "Error saving \(key): \(error.localizedDescription)")
            }
        }
    }
}
