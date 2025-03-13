import CoreData
import Foundation

final class PumpStorage {
    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    func saveBasal(_ basal: Double, date: Date) {
        guard basal > 0 else { return }
        coredataContext.perform {
            let saveBasal = Pump(context: self.coredataContext)
            saveBasal.basal = basal
            saveBasal.date = date
            try? self.coredataContext.save()
        }
        print("CoreData Basal: \(basal), Date: \(date)")
    }

    func saveBolus(_ bolus: Double) {
        guard bolus > 0 else { return }
        coredataContext.perform {
            let saveBasal = Pump(context: self.coredataContext)
            saveBasal.bolus = bolus
            saveBasal.date = Date.now
            try? self.coredataContext.save()
        }
    }
}
