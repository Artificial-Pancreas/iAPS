import Foundation

actor TaskSerializer {
    private var tail: Task<Void, Never>?

    private func swap(_ newTail: Task<Void, Never>) -> Task<Void, Never>? {
        let previous = tail
        tail = newTail
        return previous
    }

    @discardableResult func run<T>(
        isolation _: isolated(any Actor)? = #isolation,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        var openGate: AsyncStream<Void>.Continuation!
        let gate = AsyncStream<Void> { openGate = $0 }

        let predecessor = await swap(Task { for await _ in gate {} })

        await predecessor?.value // wait for the previous invocation to finish
        defer { openGate.finish() } // let the next invocation continue (if any)
        return try await operation()
    }
}
