import CoreData
import Foundation

public extension LoopStatRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<LoopStatRecord> {
        NSFetchRequest<LoopStatRecord>(entityName: "LoopStatRecord")
    }

    @NSManaged var duration: Double
    @NSManaged var end: Date?
    @NSManaged var start: Date?
    @NSManaged var loopStatus: String?
}
