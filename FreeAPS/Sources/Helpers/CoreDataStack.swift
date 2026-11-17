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

    var context: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// Runs `work` on the view context's queue (the main thread) and returns its result.
    ///
    /// Objects fetched from the view context may only be read or changed on that queue. Code running on any
    /// other queue does its reading in here and takes plain values out; a managed object must not leave the
    /// block. Safe to call from the main thread and from inside another block of the same context.
    func onViewContext<T>(_ work: () throws -> T) rethrows -> T {
        try persistentContainer.viewContext.performAndWait(work)
    }

    func saveContext() {
        let context = persistentContainer.viewContext

        guard context.hasChanges else { return }

        context.perform {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError

                debug(
                    .apsManager,
                    "Failed saving CoreData context: \(nsError), \(nsError.userInfo)"
                )
            }
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }

    func delete(_ object: NSManagedObject) {
        context.delete(object)
    }

    func deleteBatch(entity: String) {
        let request = NSBatchDeleteRequest(
            fetchRequest: NSFetchRequest<NSFetchRequestResult>(
                entityName: entity
            )
        )

        context.perform {
            do {
                debug(
                    .apsManager,
                    "Clearing \(entity) entries from CoreData."
                )

                try self.context.execute(request)

            } catch {
                debug(
                    .apsManager,
                    "Failed deleting \(entity) entries from CoreData."
                )
            }
        }
    }
}
