import CoreData
import Foundation
import SwiftDate
import Swinject

final class CoreDataStorage: Sendable {
    func fetchGlucose(interval: NSDate) async -> [ReadingsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.predicate = NSPredicate(
                format: "glucose > 0 AND date > %@", interval
            )
            let fetchGlucose = (try? context.fetch(requestReadings)) ?? []
            return fetchGlucose.map { ReadingsSnapshot.create(from: $0) }
        }
    }

    func fetchRecentGlucose() async -> ReadingsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReadings = Readings.fetchRequest() as NSFetchRequest<Readings>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReadings.sortDescriptors = [sort]
            requestReadings.fetchLimit = 1
            if let fetchGlucose = (try? context.fetch(requestReadings))?.first {
                return ReadingsSnapshot.create(from: fetchGlucose)
            } else {
                return nil
            }
        }
    }

    func fetchInsulinData(interval: NSDate) async -> [IOBEntryShort] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTicks = InsulinActivity.fetchRequest()
            let sort = NSSortDescriptor(key: "date", ascending: true)
            requestTicks.sortDescriptors = [sort]
            requestTicks.predicate = NSPredicate(
                format: "date > %@", interval
            )
            let fetchTicks = (try? context.fetch(requestTicks)) ?? []
            let result = fetchTicks.compactMap { tick -> IOBEntryShort? in
                guard let date = tick.date, let activity = tick.activity, let iob = tick.iob else {
                    return nil
                }
                return IOBEntryShort(
                    time: date,
                    iob: iob as Decimal,
                    activity: activity as Decimal
                )
            }
            return result
        }
    }

    func fetchLatestInsulinData() async -> IOBEntryShort? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTicks = InsulinActivity.fetchRequest()
            let sort = NSSortDescriptor(key: "date", ascending: true)
            requestTicks.sortDescriptors = [sort]
            requestTicks.fetchLimit = 1
            let fetchTicks = (try? context.fetch(requestTicks)) ?? []

            return fetchTicks.firstNonNil { tick -> IOBEntryShort? in
                guard let date = tick.date, let activity = tick.activity, let iob = tick.iob else {
                    return nil
                }
                return IOBEntryShort(
                    time: date,
                    iob: iob as Decimal,
                    activity: activity as Decimal
                )
            }
        }
    }

    func saveInsulinData(iobEntries: [IOBEntry]) async -> Decimal? {
        guard let firstDate = iobEntries.compactMap(\.time).min() else { return nil }
        let iob = iobEntries[0].iob

        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let deleteRequest = InsulinActivity.fetchRequest()
            deleteRequest.predicate = NSPredicate(
                format: "date >= %@ OR date < %@",
                firstDate.addingTimeInterval(-60) as NSDate, // delete previous "future" entries
                firstDate.addingTimeInterval(-86400) as NSDate // delete entries older than 1 day
            )
            do {
                let recordsToDelete = try context.fetch(deleteRequest)
                for record in recordsToDelete {
                    context.delete(record)
                }
            } catch { return }

            for iobEntry in iobEntries {
                let record = InsulinActivity(context: context)
                record.date = iobEntry.time
                record.iob = NSDecimalNumber(decimal: iobEntry.iob)
                record.activity = NSDecimalNumber(decimal: iobEntry.activity)
            }
            try? context.save()
        }
        return iob
    }

    func fetchLoopStats(interval: NSDate) async -> [LoopStatRecordSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestLoopStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sort = NSSortDescriptor(key: "start", ascending: false)
            requestLoopStats.sortDescriptors = [sort]
            requestLoopStats.predicate = NSPredicate(
                format: "interval > 0 AND start > %@", interval
            )
            let fetchLoopStats = (try? context.fetch(requestLoopStats)) ?? []
            return fetchLoopStats.map { LoopStatRecordSnapshot.create(from: $0) }
        }
    }

    func fetchTDD(interval: NSDate) async -> [TDDSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTDD = TDD.fetchRequest() as NSFetchRequest<TDD>
            requestTDD.predicate = NSPredicate(format: "timestamp > %@ AND tdd > 0", interval)
            let sortTDD = NSSortDescriptor(key: "timestamp", ascending: false)
            requestTDD.sortDescriptors = [sortTDD]
            let uniqueEvents = (try? context.fetch(requestTDD)) ?? []
            return uniqueEvents.map { TDDSnapshot.create(from: $0) }
        }
    }

    func saveTDD(_ insulin: (bolus: Decimal, basal: Decimal, hours: Double)) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveToTDD = TDD(context: context)
            saveToTDD.timestamp = Date.now
            saveToTDD.tdd = (insulin.basal + insulin.bolus) as NSDecimalNumber?
            let saveToInsulin = InsulinDistribution(context: context)
            saveToInsulin.bolus = insulin.bolus as NSDecimalNumber?
            // saveToInsulin.scheduledBasal = (suggestion.insulin?.scheduled_basal ?? 0) as NSDecimalNumber?
            saveToInsulin.tempBasal = insulin.basal as NSDecimalNumber?
            saveToInsulin.date = Date()
            try? context.save()
        }
    }

    func fetchTempTargetsSlider() async -> [TempTargetsSliderSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestIsEnbled = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
            requestIsEnbled.sortDescriptors = [sortIsEnabled]
            // requestIsEnbled.fetchLimit = 1
            let sliderArray = (try? context.fetch(requestIsEnbled)) ?? []
            return sliderArray.map { TempTargetsSliderSnapshot.create(from: $0) }
        }
    }

    func fetchTempTargets() async -> [TempTargetsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestTempTargets = TempTargets.fetchRequest() as NSFetchRequest<TempTargets>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            requestTempTargets.fetchLimit = 1
            let tempTargetsArray = (try? context.fetch(requestTempTargets)) ?? []
            return tempTargetsArray.map { TempTargetsSnapshot.create(from: $0) }
        }
    }

    /// Fetch saved meals within interval, future entries excluded
    func fetchMealData(interval: NSDate) async -> [MealsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let now = NSDate()
            let requestData = Meals.fetchRequest()
            let sortData = NSSortDescriptor(key: "actualDate", ascending: false)
            requestData.sortDescriptors = [sortData]
            requestData.predicate = NSPredicate(
                format: "savedToFile == true AND actualDate > %@ AND actualDate <= %@",
                interval,
                now
            )
            let data = (try? context.fetch(requestData)) ?? []
            print("Meal Flow: \(data.count) entries retrieved")
            return data.map { MealsSnapshot.create(from: $0) }
        }
    }

    func updateLatestMeal(to saved: Bool) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let request: NSFetchRequest<Meals> = Meals.fetchRequest()

            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Meals.createdAt, ascending: false)
            ]

            request.fetchLimit = 1

            do {
                guard let latestMeal = try context.fetch(request).first else {
                    return
                }

                latestMeal.savedToFile = saved

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                print("CoreData update failed:", error)
            }
        }
    }

    func fetchStats() async -> StatsDataSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
            let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            let stats = (try? context.fetch(requestStats)) ?? []
            return stats.map { StatsDataSnapshot.create(from: $0) }.first
        }
    }

    func fetchInsulinDistribution() async -> InsulinDistributionSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestInsulinDistribution = InsulinDistribution.fetchRequest() as NSFetchRequest<InsulinDistribution>
            let sortInsulin = NSSortDescriptor(key: "date", ascending: false)
            requestInsulinDistribution.sortDescriptors = [sortInsulin]
            requestInsulinDistribution.fetchLimit = 1
            let insulinDistribution = (try? context.fetch(requestInsulinDistribution)) ?? []
            return insulinDistribution.map { InsulinDistributionSnapshot.create(from: $0) }.first
        }
    }

    func fetchReason() async -> ReasonsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.fetchLimit = 1
            let suggestions = (try? context.fetch(requestReasons)) ?? []
            return suggestions.map { ReasonsSnapshot.create(from: $0) }.first
        }
    }

    func fetchReasons(interval: NSDate) async -> [ReasonsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.predicate = NSPredicate(
                format: "date > %@", interval
            )
            let reasonArray = (try? context.fetch(requestReasons)) ?? []
            return reasonArray.map { ReasonsSnapshot.create(from: $0) }
        }
    }

    // TODO: duplicate of fetchReason() ?
    func recentReason() async -> ReasonsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestReasons = Reasons.fetchRequest() as NSFetchRequest<Reasons>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestReasons.sortDescriptors = [sort]
            requestReasons.fetchLimit = 1
            let reasonArray = (try? context.fetch(requestReasons)) ?? []
            return reasonArray.map { ReasonsSnapshot.create(from: $0) }.first
        }
    }

    func saveStatUploadCount() async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveStatsCoreData = StatsData(context: context)
            saveStatsCoreData.lastrun = Date()
            try? context.save()
        }
        UserDefaults.standard.set(false, forKey: IAPSconfig.newVersion)
    }

    func saveVersion(_ versions: Version?) async {
        guard let version = versions else { return }
        guard version.main != "" else { return }
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let saveNr = VNr(context: context)
            saveNr.nr = version.main
            saveNr.dev = version.dev

            if context.hasChanges {
                saveNr.date = Date.now
                try? context.save()
            }
        }
    }

    func fetchVersion() async -> VNrSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestNr = VNr.fetchRequest() as NSFetchRequest<VNr>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestNr.sortDescriptors = [sort]
            requestNr.fetchLimit = 1
            let nr = (try? context.fetch(requestNr)) ?? []
            return nr.map { VNrSnapshot.create(from: $0) }.first
        }
    }

    func recentMeal() async -> MealsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestmeals = Meals.fetchRequest() as NSFetchRequest<Meals>
            let sort = NSSortDescriptor(key: "createdAt", ascending: false)
            requestmeals.sortDescriptors = [sort]
            requestmeals.fetchLimit = 1
            let meals = (try? context.fetch(requestmeals)) ?? []
            return meals.map { MealsSnapshot.create(from: $0) }.first
        }
    }

    /// Save one Meal entry
    func saveMeal(_ stored: [CarbsEntry], now: Date, savedToFile: Bool = false) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Meals(context: context)
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
                        let micro = Micronutrient(context: context)

                        micro.id = UUID()
                        micro.name = value.name
                        micro.type = value.substance.rawValue
                        micro.unit = value.unit
                        micro.amount = NSDecimalNumber(decimal: value.amount)
                        micro.meal = save

                        save.addToMicronutrients(micro)

                        print("Micro " + value.name + " \(value.amount)")
                    }
                }

                try? context.save()
            }
        }
    }

    /// Save array of meals
    func saveMeals(_ stored: [CarbsEntry]) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            stored.forEach { entry in
                let save = Meals(context: context)

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
                try context.save()
            } catch {
                print("Failed saving meals:", error)
            }
        }
    }

    func fetchMealPreset(_ name: String) async -> PresetsSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish == %@", name
            )
            requestPresets.fetchLimit = 1

            let presetsArray = (try? context.fetch(requestPresets)) ?? []

            return presetsArray.map { PresetsSnapshot.create(from: $0) }.first
        }
    }

    func fetchMealPresets() async -> [PresetsSnapshot] {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestPresets = Presets.fetchRequest() as NSFetchRequest<Presets>
            requestPresets.predicate = NSPredicate(
                format: "dish != %@", "" as String
            )
            let presetsArray = (try? context.fetch(requestPresets)) ?? []
            return presetsArray.map { PresetsSnapshot.create(from: $0) }
        }
    }

    func fetchOnbarding() async -> Bool {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestBool = Onboarding.fetchRequest() as NSFetchRequest<Onboarding>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestBool.sortDescriptors = [sort]
            requestBool.fetchLimit = 1
            return ((try? context.fetch(requestBool)) ?? []).first?.firstRun ?? true
        }
    }

    func saveOnbarding() async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Onboarding(context: context)
            save.firstRun = false
            save.date = Date.now
            try? context.save()
        }
    }

    func startOnbarding() async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Onboarding(context: context)
            save.firstRun = true
            save.date = Date.now
            try? context.save()
        }
    }

    func fetchSettingProfileName() async -> String {
        await fetchActiveProfile()
    }

    func fetchSettingProfileNames() async -> [ProfilesSnapshot]? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            let profilesArray = (try? context.fetch(requestProfiles)) ?? []
            return profilesArray.map { ProfilesSnapshot.create(from: $0) }
        }
    }

    func saveProfileSettingName(name: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Profiles(context: context)
            save.name = name
            save.date = Date.now
            try? context.save()
        }
    }

    func migrateProfileSettingName(name: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = Profiles(context: context)
            save.name = name
            save.date = Date.now
            save.uploaded = true
            try? context.save()
        }
    }

    func profileSettingUploaded(name: String) async {
        // Avoid duplicates
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in

            func fetchUniqueSettingProfileName(_ name: String) -> Bool {
                let requestProfiles = Profiles.fetchRequest() as NSFetchRequest<Profiles>
                let sort = NSSortDescriptor(key: "date", ascending: false)
                requestProfiles.sortDescriptors = [sort]
                requestProfiles.predicate = NSPredicate(
                    format: "uploaded == true && name == %@", name as String
                )
                requestProfiles.fetchLimit = 1
                return ((try? context.fetch(requestProfiles)) ?? []).isNotEmpty
            }

            if !fetchUniqueSettingProfileName(name) {
                var profile: String = name
                if profile.isEmpty {
                    profile = "default"
                }

                let save = Profiles(context: context)
                save.name = profile
                save.date = Date.now
                save.uploaded = true
                try? context.save()
            }
        }
    }

    func activeProfile(name: String) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let save = ActiveProfile(context: context)
            save.name = name
            save.date = Date.now
            save.active = true
            try? context.save()
        }
    }

    func checkIfActiveProfile() async -> Bool {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.fetchLimit = 1

            let presetsArray = (try? context.fetch(requestProfiles)) ?? []
            return (presetsArray.first?.active ?? false)
        }
    }

    func fetchActiveProfile() async -> String {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestProfiles = ActiveProfile.fetchRequest() as NSFetchRequest<ActiveProfile>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestProfiles.sortDescriptors = [sort]
            requestProfiles.fetchLimit = 1

            let presetsArray = (try? context.fetch(requestProfiles)) ?? []
            return presetsArray.first?.name ?? "default"
        }
    }

    func fetchLastLoop() async -> LastLoopSnapshot? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestLastLoop = LastLoop.fetchRequest() as NSFetchRequest<LastLoop>
            let sortLoops = NSSortDescriptor(key: "timestamp", ascending: false)
            requestLastLoop.sortDescriptors = [sortLoops]
            requestLastLoop.fetchLimit = 1
            let lastLoop = (try? context.fetch(requestLastLoop)) ?? []
            return lastLoop.map { LastLoopSnapshot.create(from: $0) }.first
        }
    }

    func insulinConcentration() async -> (concentration: Double, increment: Double) {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let requestConc = InsulinConcentration.fetchRequest() as NSFetchRequest<InsulinConcentration>
            let sort = NSSortDescriptor(key: "date", ascending: false)
            requestConc.sortDescriptors = [sort]
            requestConc.fetchLimit = 1
            let conc = (try? context.fetch(requestConc)) ?? []
            let recent = conc.first
            return (recent?.concentration ?? 1.0, recent?.incrementSetting ?? 0.1)
        }
    }

    func deleteBatch(identifier: String?, entity: String) async {
        guard let id = identifier else { return }
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { context in
            let fetchRequest: NSFetchRequest<NSFetchRequestResult>
            fetchRequest = NSFetchRequest(entityName: entity)
            fetchRequest.predicate = NSPredicate(format: "id == %@", id)
            let deleteRequest = NSBatchDeleteRequest(
                fetchRequest: fetchRequest
            )
            deleteRequest.resultType = .resultTypeObjectIDs
            do {
                let deleteResult = try context.execute(deleteRequest) as? NSBatchDeleteResult
                if let objectIDs = deleteResult?.result as? [NSManagedObjectID] {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: objectIDs],
                        into: [
                            CoreDataStack.shared.persistentContainer
                                .viewContext
                        ] // update the view context after a batch delete
                    )
                }
            } catch { debug(.apsManager, entity + "records failed to delete in batch.") }
        }
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
    @NSManaged public var id: UUID?
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
