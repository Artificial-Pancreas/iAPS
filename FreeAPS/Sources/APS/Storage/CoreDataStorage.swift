import CoreData
import Foundation
import SwiftDate
import Swinject

final class CoreDataStorage {
    let coredataContext = CoreDataStack.shared.persistentContainer.viewContext

    func fetchGlucose(interval: NSDate) -> [Readings] {
        var fetchGlucose = [Readings]()
        coredataContext.performAndWait {
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.predicate = NSPredicate(
                format: "glucose > 0 AND date > %@", interval
            )
            try? fetchGlucose = self.coredataContext.fetch(requestReadings)
        }
        return fetchGlucose
    }

    func fetchLoopStats(interval: NSDate) -> [LoopStatRecord] {
        var fetchLoopStats = [LoopStatRecord]()
        coredataContext.performAndWait {
            let requestLoopStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sort = NSSortDescriptor(key: "start", ascending: false)
            requestLoopStats.sortDescriptors = [sort]
            requestLoopStats.predicate = NSPredicate(
                format: "interval > 0 AND start > %@", interval
            )
            try? fetchLoopStats = self.coredataContext.fetch(requestLoopStats)
        }
        return fetchLoopStats
    }

    func fetchTDD(interval: NSDate) -> [TDD] {
        var uniqueEvents = [TDD]()
        coredataContext.performAndWait {
            let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
            requestTDD.predicate = NSPredicate(format: "timestamp > %@ AND tdd > 0", interval)
            let sortTDD = NSSortDescriptor(key: "timestamp", ascending: false)
            requestTDD.sortDescriptors = [sortTDD]
            try? uniqueEvents = coredataContext.fetch(requestTDD)
        }
        return uniqueEvents
    }

    func saveTDD(_ insulin: (bolus: Decimal, basal: Decimal, hours: Double)) {
        coredataContext.perform {
            let saveToTDD = TDD(context: self.coredataContext)
            saveToTDD.timestamp = Date.now
            saveToTDD.tdd = (insulin.basal + insulin.bolus) as NSDecimalNumber?
            let saveToInsulin = InsulinDistribution(context: self.coredataContext)
            saveToInsulin.bolus = insulin.bolus as NSDecimalNumber?
            // saveToInsulin.scheduledBasal = (suggestion.insulin?.scheduled_basal ?? 0) as NSDecimalNumber?
            saveToInsulin.tempBasal = insulin.basal as NSDecimalNumber?
            saveToInsulin.date = Date()
            try? self.coredataContext.save()
        }
    }

    func fetchTempTargetsSlider() -> [TempTargetsSlider] {
        var sliderArray = [TempTargetsSlider]()
        coredataContext.performAndWait {
            let requestIsEnbled = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
            requestIsEnbled.sortDescriptors = [sortIsEnabled]
            // requestIsEnbled.fetchLimit = 1
            try? sliderArray = coredataContext.fetch(requestIsEnbled)
        }
        return sliderArray
    }

    func fetchTempTargets() -> [TempTargets] {
        var tempTargetsArray = [TempTargets]()
        coredataContext.performAndWait {
            let requestTempTargets = TempTargets.fetchRequest() as NSFetchRequest<TempTargets>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            requestTempTargets.fetchLimit = 1
            try? tempTargetsArray = coredataContext.fetch(requestTempTargets)
        }
        return tempTargetsArray
    }

    func fetcarbs(interval: NSDate) -> [Carbohydrates] {
        var carbs = [Carbohydrates]()
        coredataContext.performAndWait {
            let requestCarbs = Carbohydrates.fetchRequest() as NSFetchRequest<Carbohydrates>
            requestCarbs.predicate = NSPredicate(format: "carbs > 0 AND date > %@", interval)
            let sortCarbs = NSSortDescriptor(key: "date", ascending: true)
            requestCarbs.sortDescriptors = [sortCarbs]
            try? carbs = coredataContext.fetch(requestCarbs)
        }
        return carbs
    }

    func fetchStats() -> [StatsData] {
        var stats = [StatsData]()
        coredataContext.performAndWait {
            let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
            let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            try? stats = coredataContext.fetch(requestStats)
        }
        return stats
    }

    func fetchInsulinDistribution() -> [InsulinDistribution] {
        var insulinDistribution = [InsulinDistribution]()
        coredataContext.performAndWait {
            let requestInsulinDistribution = InsulinDistribution.fetchRequest() as NSFetchRequest<InsulinDistribution>
            let sortInsulin = NSSortDescriptor(key: "date", ascending: false)
            requestInsulinDistribution.sortDescriptors = [sortInsulin]
            try? insulinDistribution = coredataContext.fetch(requestInsulinDistribution)
        }
        return insulinDistribution
    }

    func fetchReason() -> Reasons? {
        var suggestion = [Reasons]()
        coredataContext.performAndWait {
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            try? suggestion = coredataContext.fetch(requestReasons)
        }
        return suggestion.first
    }

    func fetchReasons(interval: NSDate) -> [Reasons] {
        var reasonArray = [Reasons]()
        coredataContext.performAndWait {
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.predicate = NSPredicate(
                format: "date > %@", interval
            )
            try? reasonArray = self.coredataContext.fetch(requestReasons)
        }
        return reasonArray
    }

    func saveStatUploadCount() {
        coredataContext.performAndWait { [self] in
            let saveStatsCoreData = StatsData(context: self.coredataContext)
            saveStatsCoreData.lastrun = Date()
            try? self.coredataContext.save()
        }
        UserDefaults.standard.set(false, forKey: IAPSconfig.newVersion)
    }

    func saveVNr(_ versions: Version?) {
        if let version = versions {
            coredataContext.performAndWait { [self] in
                let saveNr = VNr(context: self.coredataContext)
                saveNr.nr = version.main
                saveNr.dev = version.dev
                saveNr.date = Date.now
                try? self.coredataContext.save()
            }
        }
    }

    func fetchVNr() -> VNr? {
        var nr = [VNr]()
        coredataContext.performAndWait {
            let requestNr = VNr.fetchRequest() as NSFetchRequest<VNr>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestNr.sortDescriptors = [sort]
            requestNr.fetchLimit = 1
            try? nr = coredataContext.fetch(requestNr)
        }
        return nr.first
    }
}
