import CoreData
import Foundation

public extension TDD {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TDD> {
        NSFetchRequest<TDD>(entityName: "TDD")
    }

    @NSManaged var tdd: NSDecimalNumber?
    @NSManaged var timestamp: Date?
    @NSManaged var id: String?
}
