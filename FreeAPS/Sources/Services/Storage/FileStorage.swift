import Foundation

protocol FileStorage: Sendable {
    func save<Value: JSON>(_ value: Value, as name: String) async
    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) async -> Value?
    func retrieveRaw(_ name: String) async -> RawJSON?
    @discardableResult func append<Value: JSON>(_ newValue: Value, to name: String) async -> [Value]?
    @discardableResult func append<Value: JSON>(_ newValues: [Value], to name: String) async -> [Value]?
    @discardableResult func append<Value: JSON, T: Equatable & Sendable>(
        _ newValue: Value,
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]?
    @discardableResult func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]?
    @discardableResult func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqByProj proj: @Sendable(Value) -> T
    ) async -> [Value]?

    @discardableResult func appendAndModify<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to file: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable,
        _ modify: @Sendable([Value]) -> [Value]
    ) async -> [Value]

    @discardableResult func modify<Value: JSON>(
        file: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> [Value]
    ) async -> [Value]

    @discardableResult func delete<Value: JSON>(
        file: String,
        as type: Value.Type,
        where shouldDelete: @Sendable(Value) -> Bool
    ) async -> (kept: [Value], deleted: [Value]?)

    @discardableResult func maybeModify<Value: JSON>(
        file: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> [Value]?
    ) async -> (Bool, [Value])

    func remove(_ name: String) async
    func rename(_ name: String, to newName: String) async
    func retrieveFile<Value: JSON>(_ name: String, as type: Value.Type) async -> Value?

    func urlFor(file: String) async -> URL?
}

actor BaseFileStorage: FileStorage, Injectable {
//    nonisolated let unownedExecutor: UnownedSerialExecutor =
//        DispatchQueue(label: "BaseFileStorage.io", qos: .utility)
//            .asUnownedSerialExecutor()

    func save<Value: JSON>(_ value: Value, as name: String) {
        if let value = value as? RawJSON, let data = value.data(using: .utf8) {
            try? Disk.save(data, to: .documents, as: name)
        } else {
            try? Disk.save(value, to: .documents, as: name, encoder: JSONCoding.encoder)
        }
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        try? Disk.retrieve(name, from: .documents, as: type, decoder: JSONCoding.decoder)
    }

    func retrieveRaw(_ name: String) -> RawJSON? {
        guard let data = try? Disk.retrieve(name, from: .documents, as: Data.self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func retrieveFile<Value: JSON>(_ name: String, as type: Value.Type) -> Value? {
        if let loaded = retrieve(name, as: type) {
            return loaded
        }
        let file = retrieveRaw(name) ?? OpenAPS.defaults(for: name)
        save(file, as: name)
        return retrieve(name, as: type)
    }

    @discardableResult func append<Value: JSON>(_ newValue: Value, to name: String) async -> [Value]? {
        try? Disk.append(newValue, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
    }

    @discardableResult func append<Value: JSON>(_ newValues: [Value], to name: String) async -> [Value]? {
        try? Disk.append(newValues, to: name, in: .documents, decoder: JSONCoding.decoder, encoder: JSONCoding.encoder)
    }

    @discardableResult func append<Value: JSON, T: Equatable & Sendable>(
        _ newValue: Value,
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]? {
        await append([newValue], to: name, uniqBy: keyPath)
    }

    @discardableResult func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) async -> [Value]? {
        let values: [Value] = doRetrieve(from: name)
        let appended = Self.doAppend(newValues, existingValues: values, uniqBy: keyPath)
        save(appended, as: name)
        return appended
    }

    @discardableResult func append<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to name: String,
        uniqByProj proj: @Sendable(Value) -> T
    ) async -> [Value]? {
        let values: [Value] = doRetrieve(from: name)
        let appended = Self.doAppend(newValues, existingValues: values, uniqByProj: proj)
        save(appended, as: name)
        return appended
    }

    @discardableResult func delete<Value: JSON>(
        file: String,
        as _: Value.Type,
        where shouldDelete: @Sendable(Value) -> Bool
    ) async -> (kept: [Value], deleted: [Value]?) {
        let values: [Value] = doRetrieve(from: file)
        var kept: [Value] = []
        var deleted: [Value] = []
        for value in values {
            if shouldDelete(value) { deleted.append(value) } else { kept.append(value) }
        }
        if !deleted.isEmpty {
            save(kept, as: file)
            return (kept, deleted)
        }
        return (kept, nil)
    }

    @discardableResult func maybeModify<Value: JSON>(
        file: String,
        as _: Value.Type,
        _ modify: @Sendable([Value]) -> [Value]?
    ) async -> (Bool, [Value]) {
        let values: [Value] = doRetrieve(from: file)
        if let modified = modify(values) {
            save(modified, as: file)
            return (true, modified)
        } else {
            return (false, values)
        }
    }

    @discardableResult func modify<Value: JSON>(
        file: String,
        as type: Value.Type,
        _ modify: @Sendable([Value]) -> [Value]
    ) async -> [Value] {
        await maybeModify(file: file, as: type, modify).1
    }

    @discardableResult func appendAndModify<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        to file: String,
        uniqBy keyPath: KeyPath<Value, T> & Sendable,
        _ modify: @Sendable([Value]) -> [Value]
    ) async -> [Value] {
        await self.modify(file: file, as: Value.self) { values in
            let appended = Self.doAppend(newValues, existingValues: values, uniqBy: keyPath)
            return modify(appended)
        }
    }

    func remove(_ name: String) {
        try? Disk.remove(name, from: .documents)
    }

    func rename(_ name: String, to newName: String) {
        try? Disk.rename(name, in: .documents, to: newName)
    }

    func urlFor(file: String) -> URL? {
        try? Disk.url(for: file, in: .documents)
    }

    // ---------

    private func doRetrieve<Value: JSON>(from name: String) -> [Value] {
        retrieve(name, as: [Value].self) ??
            retrieve(name, as: Value.self).map { [$0] } ??
            []
    }

    static func doAppend<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        existingValues: [Value],
        uniqBy keyPath: KeyPath<Value, T> & Sendable
    ) -> [Value] {
        var values = existingValues
        for newValue in newValues {
            if let index = values.firstIndex(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) {
                values[index] = newValue
            } else {
                values.append(newValue)
            }
        }
        return values
    }

    static func doAppend<Value: JSON, T: Equatable & Sendable>(
        _ newValues: [Value],
        existingValues: [Value],
        uniqByProj proj: @Sendable(Value) -> T
    ) -> [Value] {
        var values = existingValues
        for newValue in newValues {
            if let index = values.firstIndex(where: { proj($0) == proj(newValue) }) {
                values[index] = newValue
            } else {
                values.append(newValue)
            }
        }
        return values
    }
}
