import Combine
import Disk
import Foundation

protocol FileStorage {
    func save<Value: JSON>(_ value: Value, as name: String) throws
    func savePublisher<Value: JSON>(_: Value, as name: String) -> AnyPublisher<Void, Error>

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) throws -> Value
    func retrievePublisher<Value: JSON>(_: String, as type: Value.Type) -> AnyPublisher<Value, Error>

    func append<Value: JSON>(_ newValue: Value, to name: String) throws
    func appendPublisher<Value: JSON>(_: Value, to name: String) -> AnyPublisher<Void, Error>
}

final class BaseFileStorage: FileStorage {
    private let processQueue = DispatchQueue(label: "BaseFileStorage.processQueue")

    func save<Value: JSON>(_ value: Value, as name: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try Disk.save(value, to: .documents, as: name, encoder: encoder)
    }

    func savePublisher<Value: JSON>(_ value: Value, as name: String) -> AnyPublisher<Void, Error> {
        Future { promise in
            self.processQueue.async {
                do {
                    try self.save(value, as: name)
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func retrieve<Value: JSON>(_ name: String, as type: Value.Type) throws -> Value {
        try Disk.retrieve(name, from: .documents, as: type)
    }

    func retrievePublisher<Value: JSON>(_ name: String, as type: Value.Type) -> AnyPublisher<Value, Error> {
        Future { promise in
            self.processQueue.async {
                do {
                    let value = try self.retrieve(name, as: type)
                    promise(.success(value))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    func append<Value: JSON>(_ newValue: Value, to name: String) throws {
        try Disk.append(newValue, to: name, in: .documents)
    }

    func appendPublisher<Value: JSON>(_ newValue: Value, to name: String) -> AnyPublisher<Void, Error> {
        Future { promise in
            self.processQueue.async {
                do {
                    try self.append(newValue, to: name)
                    promise(.success(()))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
