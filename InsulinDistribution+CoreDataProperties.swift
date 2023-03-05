import CoreData
import Foundation

public extension InsulinDistribution {
    @nonobjc class func fetchRequest() -> NSFetchRequest<InsulinDistribution> {
        NSFetchRequest<InsulinDistribution>(entityName: "InsulinDistribution")
    }

    @NSManaged var bolus: NSDecimalNumber?
    @NSManaged var tempBasal: NSDecimalNumber?
    @NSManaged var scheduledBasal: NSDecimalNumber?
    @NSManaged var date: Date?
    @NSManaged var insulin: Oref0Suggestion?
}
