import CoreData
import Foundation

/// `@unchecked Sendable`: the container is created once in `init` and only used through its thread-safe API
/// (`performBackgroundTask`, `newBackgroundContext`, merges); the mutable state is behind the locks.
final class CoreDataStack: ObservableObject, @unchecked Sendable {
    static let shared = CoreDataStack()

    /// Model only: the stores are opened by `loadStores()` (AppServices startup), before anything uses them.
    let persistentContainer: NSPersistentContainer

    private init() {
        ValueTransformer.setValueTransformer(
            NightTimeConfigurationTransformer(),
            forName: NSValueTransformerName(
                "NightTimeConfigurationTransformer"
            )
        )

        let container = NSPersistentContainer(name: "Core_Data")
        // loadStores() waits for the store (and any migration) on its own queue
        container.persistentStoreDescriptions.forEach { $0.shouldAddStoreAsynchronously = false }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        persistentContainer = container
    }

    private let loadStoresLock = NSLock()
    private var loadStoresTask: Task<Void, Error>?

    /// Opens the stores (running any migration) off the main thread. Idempotent: repeat callers await the first load,
    /// and a failed load stays failed - the store is never deleted or recreated.
    func loadStores() async throws {
        let task: Task<Void, Error> = loadStoresLock.withLock {
            if let loadStoresTask { return loadStoresTask }
            let task = Task<Void, Error> { try await self.loadPersistentStores() }
            loadStoresTask = task
            return task
        }
        try await task.value
    }

    private func loadPersistentStores() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = StoreLoadResult()
                // synchronous (shouldAddStoreAsynchronously = false): the handler runs once per store before this returns
                self.persistentContainer.loadPersistentStores { _, error in
                    if let error = error as NSError?, result.error == nil {
                        result.error = error
                    }
                }

                if let loadError = result.error {
                    debug(
                        .apsManager,
                        "Unresolved CoreData error: \(loadError), \(loadError.userInfo)"
                    )
                    warning(.apsManager, "Core Data stores failed to load", error: loadError)
                    continuation.resume(throwing: NSError(
                        domain: "APP_INIT",
                        code: 101,
                        userInfo: [
                            NSLocalizedDescriptionKey: "iAPS can't open its database: \(loadError.localizedDescription)",
                            NSUnderlyingErrorKey: loadError
                        ]
                    ))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// The first store error; written only by the synchronous `loadPersistentStores` handler, read after it returns.
    private final class StoreLoadResult: @unchecked Sendable {
        var error: NSError?
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }

    private let batchDeleteContextsLock = NSLock()
    private var batchDeleteContexts: [NSManagedObjectContext] = []

    /// Long-lived contexts (besides the viewContext) that batch deletes, which bypass the contexts, are merged into.
    func mergeBatchDeletes(into context: NSManagedObjectContext) {
        batchDeleteContextsLock.withLock { batchDeleteContexts.append(context) }
    }

    /// Merges the object IDs a batch delete returned into the viewContext and the registered contexts.
    func mergeBatchDelete(_ objectIDs: [NSManagedObjectID]) {
        let contexts = [persistentContainer.viewContext] + batchDeleteContextsLock.withLock { batchDeleteContexts }
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs], into: contexts)
    }

    func deleteBatch(entity: String) async {
        let request = NSBatchDeleteRequest(
            fetchRequest: NSFetchRequest<NSFetchRequestResult>(
                entityName: entity
            )
        )
        request.resultType = .resultTypeObjectIDs

        await persistentContainer.performBackgroundTask { context in
            do {
                debug(
                    .apsManager,
                    "Clearing \(entity) entries from CoreData."
                )

                let result = try context.execute(request) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    self.mergeBatchDelete(objectIDs)
                }
            } catch {
                debug(
                    .apsManager,
                    "Failed deleting \(entity) entries from CoreData."
                )
            }
        }
    }
}
