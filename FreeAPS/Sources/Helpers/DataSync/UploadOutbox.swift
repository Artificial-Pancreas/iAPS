import Foundation

/// A queue of items (stored in a file), waiting to be sent to an external service.
/// append-only / fire-and-forget
actor UploadOutbox<Item: JSON, Key: Hashable & Sendable> {
    private let file: String
    private let retention: TimeInterval
    private let uniqueBy: KeyPath<Item, Key> & Sendable
    private let date: @Sendable(Item) -> Date?
    private let storage: FileStorage
    private let category: Logger.Category
    private let send: @Sendable(Item) async throws -> Void

    private let serializer = TaskSerializer()

    init(
        file: String,
        retention: TimeInterval,
        uniqueBy: KeyPath<Item, Key> & Sendable,
        dateBy: KeyPath<Item, Date> & Sendable,
        storage: FileStorage,
        category: Logger.Category = .service,
        send: @escaping @Sendable(Item) async throws -> Void
    ) {
        self.file = file
        self.retention = retention
        self.uniqueBy = uniqueBy
        date = { $0[keyPath: dateBy] }
        self.storage = storage
        self.category = category
        self.send = send
    }

    init(
        file: String,
        retention: TimeInterval,
        uniqueBy: KeyPath<Item, Key> & Sendable,
        dateBy: KeyPath<Item, Date?> & Sendable,
        storage: FileStorage,
        category: Logger.Category = .service,
        send: @escaping @Sendable(Item) async throws -> Void
    ) {
        self.file = file
        self.retention = retention
        self.uniqueBy = uniqueBy
        date = { $0[keyPath: dateBy] }
        self.storage = storage
        self.category = category
        self.send = send
    }

    func enqueue(_ items: [Item]) async {
        guard items.isNotEmpty else { return }
        let cutoff = Date.now.subtractingTimeInterval(retention)
        let date = self.date
        await storage.appendAndModify(items, to: file, uniqBy: uniqueBy) { queued in
            queued.filter { item in
                guard let date = date(item) else { return false } // nil date -> ignored
                return date >= cutoff
            }
        }
    }

    /// Send queued items; remove the ones that succeed, keep failures for the next attempt.
    @discardableResult func sendPending() async -> (sent: Int, failed: Int) {
        await serializer.run {
            await self.performSendPending()
        }
    }

    private func performSendPending() async -> (sent: Int, failed: Int) {
        let cutoff = Date.now.subtractingTimeInterval(retention)
        let date = self.date
        let queued = (await storage.retrieve(file, as: [Item].self) ?? [])
            .filter { item in
                guard let date = date(item) else { return false } // nil date -> ignored
                return date >= cutoff
            }
        guard queued.isNotEmpty else { return (0, 0) }

        var sentKeys: Set<Key> = []
        var failedCount = 0
        for item in queued {
            do {
                try await send(item)
                sentKeys.insert(item[keyPath: uniqueBy])
            } catch {
                failedCount += 1
                debug(category, "outbox [\(file)]: send failed: \(error.localizedDescription)")
            }
        }

        guard sentKeys.isNotEmpty else { return (0, failedCount) }
        let uniqueBy = self.uniqueBy
        let sentKeysSnapshot = sentKeys
        await storage.modify(file: file, as: Item.self) { queued in
            queued.filter { !sentKeysSnapshot.contains($0[keyPath: uniqueBy]) }
        }
        debug(category, "outbox [\(file)]: sent \(sentKeys.count)")
        return (sentKeys.count, failedCount)
    }
}
