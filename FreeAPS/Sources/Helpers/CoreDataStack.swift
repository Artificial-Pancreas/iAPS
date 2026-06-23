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

    func deleteBatch(entity: String) {
        let request = NSBatchDeleteRequest(
            fetchRequest: NSFetchRequest<NSFetchRequestResult>(
                entityName: entity
            )
        )
        request.resultType = .resultTypeObjectIDs

        persistentContainer.performBackgroundTask { context in
            do {
                debug(
                    .apsManager,
                    "Clearing \(entity) entries from CoreData."
                )

                let result = try context.execute(request) as? NSBatchDeleteResult
                if let objectIDs = result?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [self.persistentContainer.viewContext] // update the view context after a batch delete
                    )
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
