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
