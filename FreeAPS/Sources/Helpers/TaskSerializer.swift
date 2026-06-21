actor TaskSerializer {
    private var tail: Task<Void, Never>?

    @discardableResult func run<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        let predecessor = tail
        let task = Task { () async -> Result<T, Error> in
            await predecessor?.value // wait for the previous op
            do { return .success(try await operation()) }
            catch { return .failure(error) } // capture, so the chain never breaks on throw
        }
        tail = Task { _ = await task.value }
        return try await task.value.get()
    }
}
