import Disk
import Foundation

protocol FileStorage {
    func save<Value: JSON>(_ value: Value, as name: String) throws
    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) throws -> Value
    func retrieveRaw(_ name: String) -> RawJSON?
    func append<Value: JSON>(_ newValue: Value, to name: String) throws
    func append<Value: JSON>(_ newValues: [Value], to name: String) throws
    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>) throws
    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>) throws
    func remove(_ name: String) throws
    func rename(_ name: String, to newName: String) throws
    func transaction(_ exec: (FileStorage) throws -> Void) throws

    func urlFor(file: String) -> URL?
}

final class BaseFileStorage: FileStorage {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseFileStorage.processQueue", qos: .utility)

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .customISO8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        return decoder
    }

    func save<Value: JSON>(_ value: Value, as name: String) throws {
        try processQueue.safeSync {
            if let value = value as? RawJSON, let data = value.data(using: .utf8) {
                try Disk.save(data, to: .documents, as: name)
            } else {
                try Disk.save(value, to: .documents, as: name, encoder: self.encoder)
            }
        }
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) throws -> Value {
        try processQueue.safeSync {
            try Disk.retrieve(name, from: .documents, as: type, decoder: decoder)
        }
    }

    func retrieveRaw(_ name: String) -> RawJSON? {
        processQueue.safeSync {
            guard let data = try? Disk.retrieve(name, from: .documents, as: Data.self) else {
                return nil
            }
            return String(data: data, encoding: .utf8)
        }
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) throws {
        try processQueue.safeSync {
            try Disk.append(newValue, to: name, in: .documents, decoder: decoder, encoder: encoder)
        }
    }

    func append<Value: JSON>(_ newValues: [Value], to name: String) throws {
        try processQueue.safeSync {
            try Disk.append(newValues, to: name, in: .documents, decoder: decoder, encoder: encoder)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValue: Value, to name: String, uniqBy keyPath: KeyPath<Value, T>) throws {
        if let value = try? retrieve(name, as: Value.self) {
            if value[keyPath: keyPath] != newValue[keyPath: keyPath] {
                try append(newValue, to: name)
            }
        } else if let values = try? retrieve(name, as: [Value].self) {
            guard values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil else {
                return
            }
            try append(newValue, to: name)
        } else {
            try save(newValue, as: name)
        }
    }

    func append<Value: JSON, T: Equatable>(_ newValues: [Value], to name: String, uniqBy keyPath: KeyPath<Value, T>) throws {
        if let value = try? retrieve(name, as: Value.self) {
            guard newValues.first(where: { $0[keyPath: keyPath] == value[keyPath: keyPath] }) == nil else {
                return
            }
            try append(newValues, to: name)
        } else if let values = try? retrieve(name, as: [Value].self) {
            try newValues.forEach { newValue in
                guard values.first(where: { $0[keyPath: keyPath] == newValue[keyPath: keyPath] }) == nil else {
                    return
                }
                try append(newValue, to: name)
            }
        } else {
            try save(newValues, as: name)
        }
    }

    func remove(_ name: String) throws {
        try processQueue.safeSync {
            try Disk.remove(name, from: .documents)
        }
    }

    func rename(_ name: String, to newName: String) throws {
        try processQueue.safeSync {
            try Disk.rename(name, in: .documents, to: newName)
        }
    }

    func transaction(_ exec: (FileStorage) throws -> Void) throws {
        try processQueue.safeSync {
            try exec(self)
        }
    }

    func urlFor(file: String) -> URL? {
        try? Disk.url(for: file, in: .documents)
    }
}
