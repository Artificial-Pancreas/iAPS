import CoreData
import Foundation

class CoreDataStack: ObservableObject {
    init() {}

    static let shared = CoreDataStack()

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Core_Data")

        container.loadPersistentStores(completionHandler: { _, error in
            guard let error = error as NSError? else { return }
            debug(.apsManager, "Unresolved error: \(error), \(error.userInfo)")
        })

        return container
    }()

    func saveContext() {
        let context = persistentContainer.viewContext

        context.perform {
            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    let nserror = error as NSError
                    debug(.apsManager, "Unresolved error \(nserror), \(nserror.userInfo)")
                }
            }
        }
    }

    func delete(obj: NSManagedObject) {
        persistentContainer.viewContext.delete(obj)
    }

    func deleteBatch(entity: String) {
        let context = persistentContainer.viewContext

        context.performAndWait {
            let fetchRequest: NSFetchRequest<NSFetchRequestResult>
            fetchRequest = NSFetchRequest(entityName: entity)
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: fetchRequest
            )
            do {
                debug(.apsManager, "Clear the \(entity) entries from CoreData.")
                try context.execute(deleteRequest)
            } catch { debug(.apsManager, "Couldn't delete the \(entity) entries from CoreData.") }
        }
    }
}
