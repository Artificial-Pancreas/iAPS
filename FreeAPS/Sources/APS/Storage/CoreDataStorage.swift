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

    func fetchRecentGlucose() -> Readings? {
        var fetchGlucose = [Readings]()
        coredataContext.performAndWait {
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.fetchLimit = 1
            try? fetchGlucose = self.coredataContext.fetch(requestReadings)
        }
        return fetchGlucose.first
    }

    func fetchInsulinData(interval: NSDate) -> [IOBTick0] {
        var fetchTicks = [InsulinActivity]()
        coredataContext.performAndWait {
            let requestTicks = InsulinActivity.fetchRequest() as NSFetchRequest<InsulinActivity>
            let sort = NSSortDescriptor(key: "date", ascending: true)
            requestTicks.sortDescriptors = [sort]
            requestTicks.predicate = NSPredicate(
                format: "date > %@", interval
            )
            try? fetchTicks = self.coredataContext.fetch(requestTicks)
        }
        let result = fetchTicks.compactMap { tick -> IOBTick0? in
            guard let date = tick.date, let activity = tick.activity, let iob = tick.iob else {
                return nil
            }
            return IOBTick0(
                time: date,
                iob: iob as Decimal,
                activity: activity as Decimal
            )
        }
        return result
    }

    func saveInsulinData(iobEntries: [IOBTick0]) -> Decimal? {
        guard let firstDate = iobEntries.compactMap(\.time).min() else { return nil }
        let iob = iobEntries[0].iob

        coredataContext.perform {
            let deleteRequest = InsulinActivity.fetchRequest() as NSFetchRequest<InsulinActivity>
            deleteRequest.predicate = NSPredicate(
                format: "date >= %@ OR date < %@",
                firstDate.addingTimeInterval(-60) as NSDate, // Delete previous "future" entries
                firstDate.addingTimeInterval(-86400) as NSDate // Delete entries older than 1 day
            )
            do {
                let recordsToDelete = try self.coredataContext.fetch(deleteRequest)
                for record in recordsToDelete {
                    self.coredataContext.delete(record)
                }
            } catch { return }

            for iobEntry in iobEntries {
                let record = InsulinActivity(context: self.coredataContext)
                record.date = iobEntry.time
                record.iob = NSDecimalNumber(decimal: iobEntry.iob)
                record.activity = NSDecimalNumber(decimal: iobEntry.activity)
            }
            try? self.coredataContext.save()
        }
        return iob
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
            requestInsulinDistribution.fetchLimit = 1
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
            requestReasons.fetchLimit = 1
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

    func recentReason() -> Reasons? {
        var reasonArray = [Reasons]()
        coredataContext.performAndWait {
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.fetchLimit = 1
            try? reasonArray = self.coredataContext.fetch(requestReasons)
        }
        return reasonArray.first
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
        guard let version = versions, !version.main.isEmpty else { return }
        coredataContext.perform { [self] in
            let saveNr = VNr(context: self.coredataContext)
            saveNr.nr = version.main
            saveNr.dev = version.dev

            if coredataContext.hasChanges {
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

    func recentMeal() -> Meals? {
        var meals = [Meals]()
        coredataContext.performAndWait {
            let requestmeals = Meals.fetchRequest() as NSFetchRequest<Meals>
            let sort = NSSortDescriptor(key: "createdAt", ascending: false)
            requestmeals.sortDescriptors = [sort]
            requestmeals.fetchLimit = 1
            try? meals = coredataContext.fetch(requestmeals)
        }
        return meals.first
    }

    func saveMeal(_ stored: [CarbsEntry], now: Date) {
        coredataContext.perform { [self] in
            let save = Meals(context: coredataContext)
            if let entry = stored.first {
                save.createdAt = now
                save.actualDate = entry.actualDate ?? Date.now
                save.id = entry.id ?? ""
                save.carbs = Double(entry.carbs)
                save.fat = Double(entry.fat ?? 0)
                save.protein = Double(entry.protein ?? 0)
                save.note = entry.note
                try? coredataContext.save()
            }
        }
    }

    // Optimization: Added fetchLimit to avoid fetching the entire preset library
    func fetchMealPreset(_ name: String) -> Presets? {
        var preset: Presets?
        coredataContext.performAndWait {
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish == %@", name
            )
            requestPresets.fetchLimit = 1
            preset = (try? self.coredataContext.fetch(requestPresets))?.first
        }
        return preset
    }

    func fetchMealPresets() -> [Presets] {
        var presetsArray = [Presets]()
        coredataContext.performAndWait {
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish != %@", "" as String
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)
        }
        return presetsArray
    }

    func fetchOnbarding() -> Bool {
        var firstRun = true
        coredataContext.performAndWait {
            let requestBool = Onboarding.fetchRequest() as NSFetchRequest<Onboarding>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestBool.sortDescriptors = [sort]
            requestBool.fetchLimit = 1
            try? firstRun = self.coredataContext.fetch(requestBool).first?.firstRun ?? true
        }
        return firstRun
    }

    func saveOnbarding() {
        coredataContext.performAndWait { [self] in
            let save = Onboarding(context: self.coredataContext)
            save.firstRun = false
            save.date = Date.now
            try? self.coredataContext.save()
        }
    }

    func startOnbarding() {
        coredataContext.performAndWait { [self] in
            let save = Onboarding(context: self.coredataContext)
            save.firstRun = true
            save.date = Date.now
            try? self.coredataContext.save()
        }
    }

    func fetchSettingProfileName() -> String {
        fetchActiveProfile()
    }

    func fetchSettingProfileNames() -> [Profiles]? {
        var presetsArray: [Profiles]?
        coredataContext.performAndWait {
            let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            try? presetsArray = self.coredataContext.fetch(requestProfiles)
        }
        return presetsArray
    }

    // Optimization: Replaced memory-heavy fetch with a direct database count query
    func fetchUniqueSettingProfileName(_ name: String) -> Bool {
        var count = 0
        coredataContext.performAndWait {
            let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
            requestProfiles.predicate = NSPredicate(
                format: "uploaded == true && name == %@", name as String
            )
            count = (try? self.coredataContext.count(for: requestProfiles)) ?? 0
        }
        return count > 0
    }

    func saveProfileSettingName(name: String) {
        coredataContext.perform { [self] in
            let save = Profiles(context: self.coredataContext)
            save.name = name
            save.date = Date.now
            try? self.coredataContext.save()
        }
    }

    func migrateProfileSettingName(name: String) {
        coredataContext.perform { [self] in
            let save = Profiles(context: self.coredataContext)
            save.name = name
            save.date = Date.now
            save.uploaded = true
            try? self.coredataContext.save()
        }
    }

    func profileSettingUploaded(name: String) {
        let profile = name.isEmpty ? "default" : name

        // Avoid duplicates
        if !fetchUniqueSettingProfileName(name) {
            coredataContext.perform { [self] in
                let save = Profiles(context: self.coredataContext)
                save.name = profile
                save.date = Date.now
                save.uploaded = true
                try? self.coredataContext.save()
            }
        }
    }

    func activeProfile(name: String) {
        coredataContext.perform { [self] in
            let save = ActiveProfile(context: self.coredataContext)
            save.name = name
            save.date = Date.now
            save.active = true
            try? self.coredataContext.save()
        }
    }

    // Optimization: Added fetchLimit to only check the most recent entry
    func checkIfActiveProfile() -> Bool {
        var isActive = false
        coredataContext.performAndWait {
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.fetchLimit = 1
            isActive = (try? self.coredataContext.fetch(requestProfiles))?.first?.active ?? false
        }
        return isActive
    }

    // Optimization: Added fetchLimit to prevent fetching all profiles
    func fetchActiveProfile() -> String {
        var profileName = "default"
        coredataContext.performAndWait {
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.fetchLimit = 1
            if let first = (try? self.coredataContext.fetch(requestProfiles))?.first, let name = first.name {
                profileName = name
            }
        }
        return profileName
    }

    func fetchLastLoop() -> LastLoop? {
        var lastLoop = [LastLoop]()
        coredataContext.performAndWait {
            let requestLastLoop = LastLoop.fetchRequest() as NSFetchRequest<LastLoop>
            let sortLoops = NSSortDescriptor(key: "timestamp", ascending: false)
            requestLastLoop.sortDescriptors = [sortLoops]
            requestLastLoop.fetchLimit = 1
            try? lastLoop = coredataContext.fetch(requestLastLoop)
        }
        return lastLoop.first
    }

    func insulinConcentration() -> (concentration: Double, increment: Double) {
        var conc = [InsulinConcentration]()
        coredataContext.performAndWait {
            let requestConc = InsulinConcentration.fetchRequest() as NSFetchRequest<InsulinConcentration>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestConc.sortDescriptors = [sort]
            requestConc.fetchLimit = 1
            try? conc = coredataContext.fetch(requestConc)
        }
        let recent = conc.first
        return (recent?.concentration ?? 1.0, recent?.incrementSetting ?? 0.1)
    }

    // MARK: - Meal History & Statistics Methods

    func generateMealSummariesForLastNDays(days: Int) -> [MealDaySummary] {
        let calendar = Calendar.current

        // Start date (inclusive) of the period
        let startDate = calendar.date(byAdding: .day, value: -days + 1, to: Date())!
        let interval = startDate as NSDate

        // 1. Purge macro data older than 90 days
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: Date())!
        purgeOldMealMacros(olderThan: ninetyDaysAgo)

        // 2. Load current entries (from startDate)
        let carbsEntries = fetchMealData(interval: interval)

        // Group by calendar day
        var grouped: [Date: [Carbohydrates]] = [:]

        for entry in carbsEntries {
            guard let date = entry.date else { continue }
            let day = calendar.startOfDay(for: date)
            grouped[day, default: []].append(entry)
        }

        var summaries: [MealDaySummary] = []

        // Calculate kcal from macros for each day
        for (day, entries) in grouped {
            var dayKcal = 0.0
            var dayCarbs = 0.0
            var dayFat = 0.0
            var dayProtein = 0.0

            for entry in entries {
                let carbs = entryCarbs(entry)
                let fat = entryFat(entry)
                let protein = entryProtein(entry)

                let kcal = carbs * 4.0 + fat * 9.0 + protein * 4.0
                dayKcal += kcal
                dayCarbs += carbs
                dayFat += fat
                dayProtein += protein

                // Update kcal in CoreData object (NSDecimalNumber)
                entry.kcal = NSDecimalNumber(value: kcal)
            }

            let servings = entries.count

            // Only include days with kcal > 0 in the summary
            guard dayKcal > 0 else { continue }

            let summary = MealDaySummary(
                date: day,
                kcal: dayKcal,
                carbs: dayCarbs,
                fat: dayFat,
                protein: dayProtein,
                servings: servings
            )
            summaries.append(summary)
        }

        // Save changes to CoreData
        do {
            try coredataContext.save()
        } catch {
            print("Error saving updated kcal values: \(error)")
        }

        // Return sorted by date
        summaries.sort { $0.date < $1.date }
        return summaries
    }

    // Clear old macros without destroying the entries entirely
    private func purgeOldMealMacros(olderThan date: Date) {
        coredataContext.performAndWait {
            let fetchRequest = Carbohydrates.fetchRequest() as NSFetchRequest<Carbohydrates>
            fetchRequest.predicate = NSPredicate(format: "date < %@", date as NSDate)

            do {
                let oldEntries = try coredataContext.fetch(fetchRequest)
                for entry in oldEntries {
                    entry.carbs = nil
                    entry.fat = nil
                    entry.protein = nil
                    entry.kcal = nil
                }
                if coredataContext.hasChanges {
                    try coredataContext.save()
                }
            } catch {
                print("Error purging old meal macro data: \(error)")
            }
        }
    }

    func fetchMealData(interval: NSDate) -> [Carbohydrates] {
        var data = [Carbohydrates]()
        coredataContext.performAndWait {
            let requestData = Carbohydrates.fetchRequest() as NSFetchRequest<Carbohydrates>
            let sortData = NSSortDescriptor(key: "date", ascending: false)
            requestData.sortDescriptors = [sortData]
            requestData.predicate = NSPredicate(
                format: "date > %@", interval
            )
            try? data = self.coredataContext.fetch(requestData)
        }
        return data
    }

    private func entryCarbs(_ entry: Carbohydrates) -> Double {
        entry.carbs?.doubleValue ?? 0
    }

    private func entryFat(_ entry: Carbohydrates) -> Double {
        entry.fat?.doubleValue ?? 0
    }

    private func entryProtein(_ entry: Carbohydrates) -> Double {
        entry.protein?.doubleValue ?? 0
    }

    // Kcal entry calculation
    private func entryKcal(_ entry: Carbohydrates) -> Double {
        if let stored = entry.kcal?.doubleValue {
            return stored
        }
        let carbs = entryCarbs(entry)
        let fat = entryFat(entry)
        let protein = entryProtein(entry)
        return carbs * 4.0 + fat * 9.0 + protein * 4.0
    }
}
