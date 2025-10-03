import Foundation

actor AsyncSerial {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @Sendable() async throws -> T) async throws -> T {
        await acquire()
        defer { release() }

        return try await operation()
    }

    func runNoThrow<T: Sendable>(_ operation: () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiters.append(cont)
        }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isHeld = false
        }
    }
}
