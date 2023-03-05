import CoreData
import Foundation

public extension Carbohydrates {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Carbohydrates> {
        NSFetchRequest<Carbohydrates>(entityName: "Carbohydrates")
    }

    @NSManaged var date: Date?
    @NSManaged var carbs: NSDecimalNumber?
    @NSManaged var enteredBy: String?
}
