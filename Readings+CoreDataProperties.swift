import CoreData
import Foundation

public extension Readings {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Readings> {
        NSFetchRequest<Readings>(entityName: "Readings")
    }

    @NSManaged var date: Date?
    @NSManaged var glucose: Int16
}
