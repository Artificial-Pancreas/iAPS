import CoreData
import Foundation

public extension Carbohydrates {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Carbohydrates> {
        NSFetchRequest<Carbohydrates>(entityName: "Carbohydrates")
    }

    @NSManaged var carbs: NSDecimalNumber?
    @NSManaged var date: Date?
    @NSManaged var enteredBy: String?
}
