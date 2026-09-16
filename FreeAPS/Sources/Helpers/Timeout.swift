import Foundation

struct TimeoutError: LocalizedError, Sendable {
    let name: String
    let duration: Duration

    var errorDescription: String? {
        "\(name) timed out after \(duration.components.seconds)s"
    }
}

func withTimeout<T: Sendable>(
    _ name: String,
    _ duration: Duration,
    _ work: @escaping @Sendable() async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await work()
        }

        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError(name: name, duration: duration)
        }

        defer { group.cancelAll() }

        guard let result = try await group.next() else {
            throw TimeoutError(name: name, duration: duration)
        }

        return result
    }
}
