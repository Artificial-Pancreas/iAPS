import CoreData
import Foundation

final class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Core_Data")

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                debug(
                    .apsManager,
                    "Unresolved CoreData error: \(error), \(error.userInfo)"
                )
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    private init() {
        ValueTransformer.setValueTransformer(
            NightTimeConfigurationTransformer(),
            forName: NSValueTransformerName(
                "NightTimeConfigurationTransformer"
            )
        )
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
