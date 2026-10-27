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

    /// Drop queued items that haven't been sent yet.
    /// Not serialized with `sendPending` (it must not wait for the network): an item already picked up by an
    /// in-flight send still gets sent.
    func discard(_ keys: Set<Key>) async {
        let uniqueBy = self.uniqueBy
        await storage.modify(file: file, as: Item.self) { queued in
            queued.filter { !keys.contains($0[keyPath: uniqueBy]) }
        }
    }

    /// Send queued items; remove the ones that succeed, keep failures for the next attempt.
    @discardableResult func sendPending() async -> (sent: Int, failed: Int) {
        let result = await sendPending(using: send)
        return (result.sent, result.failed)
    }

    /// `sendPending` with a sender for this call only (e.g. one that adds data to some of the items)
    /// - Parameter stopWhen: ends the pass at a failure it matches (the network is down: the rest would only time out)
    @discardableResult func sendPending(
        using send: @Sendable(Item) async throws -> Void,
        stopWhen: (@Sendable(Error) -> Bool)? = nil
    ) async -> (sent: Int, failed: Int, stopped: Bool) {
        await serializer.run {
            await self.performSendPending(send: send, stopWhen: stopWhen)
        }
    }

    /// the queued items, in queue order
    func pending() async -> [Item] {
        let cutoff = Date.now.subtractingTimeInterval(retention)
        let date = self.date
        return (await storage.retrieve(file, as: [Item].self) ?? [])
            .filter { item in
                guard let date = date(item) else { return false } // nil date -> ignored
                return date >= cutoff
            }
    }

    private func performSendPending(
        send: @Sendable(Item) async throws -> Void,
        stopWhen: (@Sendable(Error) -> Bool)?
    ) async -> (sent: Int, failed: Int, stopped: Bool) {
        let queued = await pending()
        guard queued.isNotEmpty else { return (0, 0, false) }

        // the sent revision of each key: an item replaced (same key) while its send was in flight stays queued
        var sentRevisions: [Key: Data] = [:]
        var failedCount = 0
        var stopped = false
        for item in queued {
            do {
                try await send(item)
                sentRevisions[item[keyPath: uniqueBy]] = Self.revision(of: item)
            } catch {
                failedCount += 1
                debug(category, "outbox [\(file)]: send failed: \(error.localizedDescription)")
                if stopWhen?(error) == true {
                    stopped = true
                    break
                }
            }
        }

        guard sentRevisions.isNotEmpty else { return (0, failedCount, stopped) }
        let uniqueBy = self.uniqueBy
        let sent = sentRevisions
        await storage.modify(file: file, as: Item.self) { queued in
            queued.filter { item in
                guard let sentRevision = sent[item[keyPath: uniqueBy]] else { return true }
                return Self.revision(of: item) != sentRevision
            }
        }
        debug(category, "outbox [\(file)]: sent \(sent.count)")
        return (sent.count, failedCount, stopped)
    }

    /// (an item that can't be encoded acts as unchanged - removed by key, as before)
    private static func revision(of item: Item) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(item)) ?? Data()
    }
}
