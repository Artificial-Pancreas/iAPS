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
            let requestTicks = InsulinActivity.fetchRequest()
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
            let deleteRequest = InsulinActivity.fetchRequest()
            deleteRequest.predicate = NSPredicate(
                format: "date >= %@ OR date < %@",
                firstDate.addingTimeInterval(-60) as NSDate, // delete previous "future" entries
                firstDate.addingTimeInterval(-86400) as NSDate // delete entries older than 1 day
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

    /// Fetch saved meals within interval, future entries excluded
    func fetchMealData(interval: NSDate) -> [Meals] {
        var data = [Meals]()
        let now = NSDate()
        coredataContext.performAndWait {
            let requestData = Meals.fetchRequest()
            let sortData = NSSortDescriptor(key: "actualDate", ascending: false)
            requestData.sortDescriptors = [sortData]
            requestData.predicate = NSPredicate(
                format: "savedToFile == true AND actualDate > %@ AND actualDate <= %@",
                interval,
                now
            )
            try? data = self.coredataContext.fetch(requestData)
        }
        print("Meal Flow: \(data.count) entries retrieved")

        return data
    }

    func updateLatestMeal(to saved: Bool) {
        coredataContext.perform {
            let request: NSFetchRequest<Meals> = Meals.fetchRequest()

            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Meals.createdAt, ascending: false)
            ]

            request.fetchLimit = 1

            do {
                guard let latestMeal = try self.coredataContext.fetch(request).first else {
                    return
                }

                latestMeal.savedToFile = saved

                if self.coredataContext.hasChanges {
                    try self.coredataContext.save()
                }
            } catch {
                print("CoreData update failed:", error)
            }
        }
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
        guard let version = versions else { return }
        guard version.main != "" else { return }
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

    /// Save one Meal entry
    func saveMeal(_ stored: [CarbsEntry], now: Date, savedToFile: Bool = false) {
        coredataContext.perform { [self] in
            let save = Meals(context: coredataContext)
            if let entry = stored.first {
                save.createdAt = now
                save.actualDate = entry.actualDate ?? entry.createdAt
                save.id = entry.id ?? ""
                save.carbs = entry.carbs as NSDecimalNumber
                save.fat = (entry.fat ?? 0) as NSDecimalNumber
                save.protein = (entry.protein ?? 0) as NSDecimalNumber
                save.fiber = (entry.fiber ?? 0) as NSDecimalNumber
                save.note = entry.note
                save.savedToFile = savedToFile

                // MARK: Are there any micronutrients?

                if let micros = entry.micronutrient {
                    print("Micro exist")
                    for value in micros {
                        guard value.amount != 0 else { continue }
                        let micro = Micronutrient(context: self.coredataContext)

                        micro.name = value.name
                        micro.type = value.substance.rawValue
                        micro.unit = value.unit
                        micro.amount = NSDecimalNumber(decimal: value.amount)
                        micro.meal = save

                        save.addToMicronutrients(micro)

                        print("Micro " + value.name + " \(value.amount)")
                    }
                }

                try? coredataContext.save()
            }
        }
    }

    /// Save array of meals
    func saveMeals(_ stored: [CarbsEntry]) {
        coredataContext.perform { [weak self] in
            guard let self else { return }

            stored.forEach { entry in
                let save = Meals(context: self.coredataContext)

                save.createdAt = entry.createdAt
                save.actualDate = entry.actualDate ?? .now
                save.id = entry.id ?? ""
                save.carbs = entry.carbs as NSDecimalNumber
                save.fat = (entry.fat ?? 0) as NSDecimalNumber
                save.protein = (entry.protein ?? 0) as NSDecimalNumber
                save.fiber = (entry.fiber ?? 0) as NSDecimalNumber
                save.note = entry.note
                save.savedToFile = true
            }

            do {
                try coredataContext.save()
            } catch {
                print("Failed saving meals:", error)
            }
        }
    }

    func fetchMealPreset(_ name: String) -> Presets? {
        var presetsArray = [Presets]()
        var preset: Presets?
        coredataContext.performAndWait {
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish == %@", name
            )
            try? presetsArray = self.coredataContext.fetch(requestPresets)

            guard let mealPreset = presetsArray.first else {
                return
            }
            preset = mealPreset
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

    func fetchUniqueSettingProfileName(_ name: String) -> Bool {
        var presetsArray: Profiles?
        coredataContext.performAndWait {
            let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.predicate = NSPredicate(
                format: "uploaded == true && name == %@", name as String
            )
            try? presetsArray = self.coredataContext.fetch(requestProfiles).first
        }
        return (presetsArray != nil)
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
        var profile: String = name
        if profile.isEmpty {
            profile = "default"
        }

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

    func checkIfActiveProfile() -> Bool {
        var presetsArray = [ActiveProfile]()
        coredataContext.performAndWait {
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            try? presetsArray = self.coredataContext.fetch(requestProfiles)
        }
        return (presetsArray.first?.active ?? false)
    }

    func fetchActiveProfile() -> String {
        var presetsArray = [ActiveProfile]()
        coredataContext.performAndWait {
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            try? presetsArray = self.coredataContext.fetch(requestProfiles)
        }
        return presetsArray.first?.name ?? "default"
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
}

// public typealias PresetsCoreDataClassSet = NSSet

@objc(Presets) class Presets: NSManagedObject {
    @NSManaged public var carbs: NSDecimalNumber?
    @NSManaged public var dish: String?
    @NSManaged public var fat: NSDecimalNumber?
    @NSManaged public var fiber: NSDecimalNumber?
    @NSManaged public var foodID: UUID?
    @NSManaged public var glycemicIndex: NSDecimalNumber?
    @NSManaged public var imageURL: String?
    @NSManaged public var mealUnits: String?
    @NSManaged public var per100: Bool
    @NSManaged public var portionSize: NSDecimalNumber?
    @NSManaged public var protein: NSDecimalNumber?
    @NSManaged public var standardName: String?
    @NSManaged public var standardServing: String?
    @NSManaged public var standardServingSize: NSDecimalNumber?
    @NSManaged public var sugars: NSDecimalNumber?
    @NSManaged public var tags: String?
    @NSManaged public var micronutrient: Set<PresetMicronutrient>?
}

@objc(Micronutrient) class Micronutrient: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String?
    @NSManaged public var type: String
    @NSManaged public var amount: NSDecimalNumber?
    @NSManaged public var unit: String?
    @NSManaged public var entries: Set<PresetMicronutrient>
}

@objc(PresetMicronutrient) class PresetMicronutrient: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged var amount: NSDecimalNumber?
    @NSManaged var per100: Bool
    @NSManaged var preset: Presets
    @NSManaged var micronutrient: Micronutrient
}

extension Presets {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Presets> {
        NSFetchRequest<Presets>(entityName: "Presets")
    }

    @objc(addMicronutrientObject:)
    @NSManaged public func addToMicronutrients(_ value: PresetMicronutrient)

    @objc(removeMicronutrientsObject:)
    @NSManaged public func removeFromMicronutrients(_ value: PresetMicronutrient)

    @objc(addMicronutrients:)
    @NSManaged public func addToMicronutrients(_ values: NSSet)

    @objc(removeMicronutrients:)
    @NSManaged public func removeFromMicronutrients(_ values: NSSet)

    func micronutrientValues() -> [PresetMicronutrient] {
        let set = micronutrient ?? []

        return set.sorted {
            ($0.micronutrient.name ?? "") < ($1.micronutrient.name ?? "")
        }
    }

    func setMicronutrient(
        name: String,
        type: String,
        unit: String,
        amount: Decimal,
        per100: Bool,
        context: NSManagedObjectContext
    ) throws {
        // 1. Fetch or create Micronutrient definition
        let micronutrient: Micronutrient

        if let existing = try Micronutrient.fetchByName(name, context: context) {
            micronutrient = existing
        } else {
            let new = Micronutrient(context: context)
            new.id = UUID()
            new.name = name
            new.type = type
            new.unit = unit
            micronutrient = new
        }

        // 2. Check if this preset already has this micronutrient
        let existingEntry = (self.micronutrient ?? [])
            .first(where: { $0.micronutrient == micronutrient })

        if let entry = existingEntry {
            // Update
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
        } else {
            // Create
            let entry = PresetMicronutrient(context: context)
            entry.id = UUID()
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
            entry.preset = self
            entry.micronutrient = micronutrient
        }
    }

    func replaceMicronutrients(
        with values: [(name: String, type: String, unit: String, amount: Decimal, per100: Bool)],
        context: NSManagedObjectContext
    ) throws {
        // Remove
        if let existing = micronutrient {
            for item in existing {
                context.delete(item)
            }
        }

        // New
        for value in values {
            try setMicronutrient(
                name: value.name,
                type: value.type,
                unit: value.unit,
                amount: value.amount,
                per100: value.per100,
                context: context
            )
        }
    }

    func allNutrients() -> [NutrientValue] {
        var results: [NutrientValue] = []

        // Macro nutrients
        if let carbs = carbs?.decimalValue {
            results.append(NutrientValue(name: "Carbs", amount: carbs, unit: "g"))
        }

        if let fat = fat?.decimalValue {
            results.append(NutrientValue(name: "Fat", amount: fat, unit: "g"))
        }

        if let protein = protein?.decimalValue {
            results.append(NutrientValue(name: "Protein", amount: protein, unit: "g"))
        }

        if let fiber = fiber?.decimalValue {
            results.append(NutrientValue(name: "Fiber", amount: fiber, unit: "g"))
        }

        if let sugars = sugars?.decimalValue {
            results.append(NutrientValue(name: "Sugars", amount: sugars, unit: "g"))
        }

        // Micronutrients
        let micros = micronutrientValuesTyped()

        for micro in micros {
            results.append(
                NutrientValue(
                    name: micro.name,
                    amount: micro.amount,
                    unit: micro.unit
                )
            )
        }
        return results
    }

    func applyMicronutrients(
        from values: [MicronutrientValue],
        context: NSManagedObjectContext
    ) throws {
        for value in values {
            try setMicronutrient(
                value.substance,
                amount: value.amountPer100,
                per100: true,
                context: context
            )
        }
    }

    func replaceMicronutrients(
        from values: [MicronutrientValue],
        context: NSManagedObjectContext
    ) throws {
        if let existing = micronutrient {
            for entry in existing {
                context.delete(entry)
            }
        }

        for value in values where value.amount > 0 || value.amountPer100 > 0 {
            try setMicronutrient(
                value.substance,
                amount: value.amountPer100,
                per100: true,
                context: context
            )
        }
    }

    func setMicronutrient(
        _ nutrient: MicroNutrient,
        amount: Decimal,
        per100: Bool,
        context: NSManagedObjectContext
    ) throws {
        let definition: Micronutrient

        if let existing = try Micronutrient.fetchByName(
            nutrient.coreDataName,
            context: context
        ) {
            definition = existing
            definition.type = nutrient.coreDataType
            definition.unit = nutrient.unit
        } else {
            let new = Micronutrient(context: context)
            new.id = UUID()
            new.name = nutrient.coreDataName
            new.type = nutrient.coreDataType
            new.unit = nutrient.unit
            definition = new
        }

        let existingEntry = (micronutrient ?? [])
            .first { $0.micronutrient == definition }

        if let entry = existingEntry {
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
        } else {
            let entry = PresetMicronutrient(context: context)
            entry.id = UUID()
            entry.amount = NSDecimalNumber(decimal: amount)
            entry.per100 = per100
            entry.preset = self
            entry.micronutrient = definition
        }
    }

    func micronutrientValuesTyped() -> [MicronutrientValue] {
        (micronutrient ?? [])
            .compactMap { entry in
                guard
                    let name = entry.micronutrient.name,
                    let substance = MicroNutrient(coreDataName: name),
                    let storedAmount = entry.amount?.decimalValue
                else {
                    return nil
                }

                let amountPer100: Decimal
                let amount: Decimal

                if entry.per100 {
                    amountPer100 = storedAmount

                    if let portion = portionSize?.decimalValue, portion > 0 {
                        amount = storedAmount / 100 * portion
                    } else {
                        amount = storedAmount
                    }
                } else {
                    amount = storedAmount

                    if let portion = portionSize?.decimalValue, portion > 0 {
                        amountPer100 = storedAmount / portion * 100
                    } else {
                        amountPer100 = storedAmount
                    }
                }

                return MicronutrientValue(
                    substance: substance,
                    amount: amount,
                    amountPer100: amountPer100
                )
            }
            .sorted { $0.name < $1.name }
    }
}

extension Micronutrient {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Micronutrient> {
        NSFetchRequest<Micronutrient>(entityName: "Micronutrient")
    }

    static func fetchAll(
        context: NSManagedObjectContext
    ) throws -> [Micronutrient] {
        let request: NSFetchRequest<Micronutrient> = Micronutrient.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "type", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return try context.fetch(request)
    }

    static func fetchByName(
        _ name: String,
        context: NSManagedObjectContext
    ) throws -> Micronutrient? {
        let request: NSFetchRequest<Micronutrient> = Micronutrient.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[c] %@", name)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    @NSManaged public var meal: Meals?
}

struct NutrientValue {
    let name: String
    let amount: Decimal
    let unit: String
}

@objc(NightTimeConfigurationBox) public final class NightTimeConfigurationBox: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let enabled: Bool

    init(_ value: NightTimeConfiguration) {
        startHour = value.startHour
        startMinute = value.startMinute
        endHour = value.endHour
        endMinute = value.endMinute
        enabled = value.enabled
        super.init()
    }

    var value: NightTimeConfiguration {
        NightTimeConfiguration(
            startHour: startHour,
            startMinute: startMinute,
            endHour: endHour,
            endMinute: endMinute,
            enabled: enabled
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(startHour, forKey: "startHour")
        coder.encode(startMinute, forKey: "startMinute")
        coder.encode(endHour, forKey: "endHour")
        coder.encode(endMinute, forKey: "endMinute")
        coder.encode(enabled, forKey: "enabled")
    }

    public required init?(coder: NSCoder) {
        startHour = coder.decodeInteger(forKey: "startHour")
        startMinute = coder.decodeInteger(forKey: "startMinute")
        endHour = coder.decodeInteger(forKey: "endHour")
        endMinute = coder.decodeInteger(forKey: "endMinute")
        enabled = coder.decodeBool(forKey: "enabled")
        super.init()
    }
}

public typealias MealsCoreDataClassSet = NSSet
@objc(Meals)
public class Meals: NSManagedObject {}

public typealias MealsCoreDataPropertiesSet = NSSet

extension Meals {
    @nonobjc class func fetchRequest() -> NSFetchRequest<Meals> {
        NSFetchRequest<Meals>(entityName: "Meals")
    }

    @NSManaged var carbs: NSDecimalNumber?
    @NSManaged var date: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var actualDate: Date?
    @NSManaged var enteredBy: String?
    @NSManaged var fat: NSDecimalNumber?
    @NSManaged var id: String?
    @NSManaged var note: String?
    @NSManaged var protein: NSDecimalNumber?
    @NSManaged var fiber: NSDecimalNumber?
    @NSManaged var fpuID: String?
    @NSManaged var savedToFile: Bool
    @NSManaged var micronutrient: NSSet?

    @NSManaged public var micronutrientsData: Data?

    @objc(addMicronutrientObject:)
    @NSManaged func addToMicronutrients(_ value: Micronutrient)

    @objc(removeMicronutrientsObject:)
    @NSManaged func removeFromMicronutrients(_ value: Micronutrient)

    @objc(addMicronutrients:)
    @NSManaged func addToMicronutrients(_ values: Set<Micronutrient>)

    @objc(removeMicronutrients:)
    @NSManaged func removeFromMicronutrients(_ values: Set<Micronutrient>)

    var micronutrientTotals: [MicroNutrient: Decimal] {
        guard let micronutrients = micronutrient as? Set<Micronutrient> else {
            return [:]
        }

        return Dictionary(
            uniqueKeysWithValues: micronutrients.compactMap { item -> (MicroNutrient, Decimal)? in
                guard let nutrient = MicroNutrient(rawValue: item.type), let amount = item.amount else {
                    return nil
                }

                return (
                    nutrient,
                    amount as Decimal
                )
            }
        )
    }

    var micronutrientValues: [MicronutrientValue] {
        guard let items = micronutrient?.allObjects as? [Micronutrient] else {
            return []
        }

        return items.compactMap { item in
            guard let substance = MicroNutrient(rawValue: item.type), let amount = item.amount?.decimalValue else {
                return nil
            }

            return MicronutrientValue(
                substance: substance,
                amount: amount,
                amountPer100: 0
            )
        }
        .sorted { $0.name < $1.name }
    }
}
