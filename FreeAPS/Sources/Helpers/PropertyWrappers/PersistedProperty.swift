import Foundation

@propertyWrapper public struct PersistedProperty<Value>: Sendable {
    let key: String
    let storageURL: URL
    /// What the file holds, as last read or written - shared by copies of this struct. No other property is of the
    /// same file. Nil: not deduplicated (the app group's file can be written by other processes).
    private let file: StoredFile?

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
        file = shared ? nil : StoredFile()
    }

    /// A file of this process only, at `storageURL` - for tests
    init(key: String, storageURL: URL) {
        self.key = key
        self.storageURL = storageURL
        file = StoredFile()
    }

    // A value equal to the one the file holds is not written again: pump and CGM managers report their state many
    // times a minute, mostly unchanged. Not debounced: a changed state goes to disk right away - the app can be killed
    // any moment, and a pump state written late can lose a session or a record sequence.
    public var wrappedValue: Value? {
        get {
            guard let file else {
                return read()
            }
            return file.withLock { stored in
                let object = readObject()
                stored.object = object.map { $0 as AnyObject }
                return value(of: object)
            }
        }
        nonmutating set {
            guard let file else {
                write(newValue)
                return
            }
            file.withLock { stored in
                guard let newValue else {
                    stored.object = nil
                    delete()
                    return
                }
                if let object = stored.object, (newValue as AnyObject).isEqual(object) {
                    stored.skipped += 1
                    return
                }
                // Written atomically: a failed write leaves the file as it was, and what is known of it
                if let data = write(newValue, skipped: stored.skipped) {
                    // As the file holds it: immutable, in the plist's own types
                    stored.object = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
                        .map { $0 as AnyObject }
                    stored.skipped = 0
                }
            }
        }
    }

    private func read() -> Value? {
        value(of: readObject())
    }

    private func readObject() -> Any? {
        do {
            let data = try Data(contentsOf: storageURL)
            debug(.openAPS, "Reading \(key) from \(storageURL.absoluteString)")
            return try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            debug(.openAPS, "Error reading \(key): \(error.localizedDescription)")
        }
        return nil
    }

    private func value(of object: Any?) -> Value? {
        guard let object else {
            return nil
        }
        guard let value = object as? Value else {
            debug(.openAPS, "Unexpected type for \(key)")
            return nil
        }
        return value
    }

    private func write(_ newValue: Value?) {
        guard let newValue else {
            delete()
            return
        }
        write(newValue, skipped: 0)
    }

    /// Returns the bytes written - nil, nothing was
    @discardableResult private func write(_ newValue: Value, skipped: Int) -> Data? {
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: newValue, format: .binary, options: 0)
            try data.write(to: storageURL, options: .atomic)
            debug(
                .openAPS,
                "Wrote \(key) to \(storageURL.absoluteString)" +
                    (skipped > 0 ? " (\(skipped) unchanged not written since the last write)" : "")
            )
            return data
        } catch {
            debug(.openAPS, "Error saving \(key): \(error.localizedDescription)")
        }
        return nil
    }

    private func delete() {
        do {
            try FileManager.default.removeItem(at: storageURL)
        } catch {
            debug(.openAPS, "Error deleting \(key): \(error.localizedDescription)")
        }
    }
}

/// What a plist file holds, as last read or written by this process. Reads and writes of the file go under its lock: a
/// read finishing after a write cannot leave the older value here.
private final class StoredFile: @unchecked Sendable {
    struct Stored {
        /// The plist object the file holds. Nil: not known, the next value is written.
        var object: AnyObject?
        /// Values not written since the last write, being the same
        var skipped = 0
    }

    private let lock = NSLock()
    private var stored = Stored()

    func withLock<T>(_ body: (inout Stored) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&stored)
    }
}
