import CoreData
import Foundation

public extension Override {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Override> {
        NSFetchRequest<Override>(entityName: "Override")
    }

    @NSManaged var date: Date?
    @NSManaged var duration: NSDecimalNumber?
    @NSManaged var enabled: Bool
    @NSManaged var indefinite: Bool
    @NSManaged var percentage: Double
    @NSManaged var timeLeft: Double
}
