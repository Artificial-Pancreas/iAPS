import Foundation
import SwiftDate
import Swinject

/// Every carbs entry that is stored gets its Meals row here (`storeMeal`, `replaceMeal`, `storeDownloadedCarbs`), and
/// every one that is deleted loses it (`deleteCarbsAndFPUs`): the carbs file and the Meals rows stay in step (the raw
/// JSON editor, `saveRawJSON`, aside). After a change of the file or a row, `appCoordinator.sendMealsChanged()` (the
/// Meals tab's refresh); a Nightscout poll that changes nothing sends nothing
protocol CarbsStorage: Sendable {
    /// A meal entered on this phone, the Watch, a shortcut or a remote command
    func storeMeal(_ entry: CarbsEntry) async
    /// A meal edited on this phone: the meal created at `createdAt` (with its FPU entries and Meals row) is replaced by
    /// `entry`, in one step
    func replaceMeal(createdAt: Date, with entry: CarbsEntry) async
    /// The carbs fetched from Nightscout
    func storeDownloadedCarbs(_ entries: [CarbsEntry]) async
    func syncDate() async -> Date
    /// Deletes the meal created at `date` with its FPU entries, and its Meals row
    func deleteCarbsAndFPUs(at date: Date) async

    func saveRawJSON(_ raw: RawJSON) async throws
}

/// The Meals rows of the carbs entries (Core Data)
protocol MealRowStore: Sendable {
    /// Upserts a row per entry, by id
    func saveMeals(_ entries: [CarbsEntry]) async
    func deleteMeals(ids: [String]) async
    /// Once: drops the duplicate rows of each id (an older version saved a downloaded meal again on every fetch). Long:
    /// not on the start path
    func deduplicateMealsOnce() async
}

actor BaseCarbsStorage: CarbsStorage, AppService {
    private let storage: FileStorage
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator
    private let mealRows: MealRowStore
    private let carbsFile: String
    /// Every change runs whole (rows, file, publish) before the next one starts: the published carbs are the file's
    private let serializer = TaskSerializer()

    init(
        storage: FileStorage,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator,
        mealRows: MealRowStore = CoreDataStorage(),
        carbsFile: String = OpenAPS.Monitor.carbHistory
    ) {
        self.storage = storage
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
        self.mealRows = mealRows
        self.carbsFile = carbsFile
    }

    // this is called on app start
    func start() async {
        let rows = await serializer.run { () async -> MigratedMealRows? in
            let rows = await migrateOldSplitsOnce()
            await resetCache()
            return rows
        }
        // in the background: the loop doesn't wait for it, and it doesn't touch the carbs file. The migration's rows
        // after the deduplication (it deletes rows of the same ids)
        let mealRows = self.mealRows
        Task(priority: .background) {
            await mealRows.deduplicateMealsOnce()
            if let rows {
                await self.writeMigratedRows(rows)
            }
        }
    }

    /// The downloads' rows as the file has them now (a poll may have changed one since the migration)
    private func writeMigratedRows(_ rows: MigratedMealRows) async {
        await serializer.run {
            await mealRows.deleteMeals(ids: rows.delete)
            let carbs = await storage.retrieve(carbsFile, as: [CarbsEntry].self) ?? []
            let save = Self.migratedMealRows(before: carbs, after: carbs).save
            if save.isNotEmpty {
                await mealRows.saveMeals(save)
            }
            if rows.delete.isNotEmpty || save.isNotEmpty {
                appCoordinator.sendMealsChanged()
            }
        }
    }

    func saveRawJSON(_ raw: RawJSON) async throws {
        try await serializer.run {
            try await storage.save(raw: raw, as: carbsFile, decodingInto: [CarbsEntry].self)
            await resetCache()
            appCoordinator.sendMealsChanged()
        }
    }

    private func resetCache() async {
        // newest -> oldest
        let carbs = await storage.retrieve(carbsFile, as: [CarbsEntry].self) ?? []
        appCoordinator.setCarbHistory(carbs)
    }

    func storeMeal(_ entry: CarbsEntry) async {
        await serializer.run {
            await doStoreMeal(entry)
        }
    }

    func replaceMeal(createdAt: Date, with entry: CarbsEntry) async {
        await serializer.run {
            // published once, with the new meal
            await doDeleteCarbsAndFPUs(at: createdAt, publish: false)
            await doStoreMeal(entry)
        }
    }

    /// A user-confirmed meal: the Meals row (+ micronutrients, savedToFile) first, then the carbs file (+ FPU split).
    /// Row first: Home refreshes its meal totals on the carbHistory publish of storeCarbs
    private func doStoreMeal(_ entry: CarbsEntry) async {
        await mealRows.saveMeals([entry])
        await storeCarbs([entry])
        appCoordinator.sendMealsChanged()
    }

    /// Fetched again on every poll (the last 24 h). Merged by the Nightscout id, each meal split into its carb
    /// equivalents once (see `mergeDownloaded`); the rows of the added or changed meals are upserted by the Nightscout id
    func storeDownloadedCarbs(_ entries: [CarbsEntry]) async {
        await serializer.run {
            let settings = await settingsManager.settings
            let fpu = FPUSettings(settings)
            let conversion = settings.fatProteinConversion
            let now = Date()
            let (changed, carbs, meals) = await storage.maybeModifyWithData(
                file: carbsFile,
                as: CarbsEntry.self
            ) { stored -> ([CarbsEntry], data: [CarbsEntry])? in
                let merge = BaseCarbsStorage.mergeDownloaded(
                    entries,
                    into: stored,
                    fpu: fpu,
                    fatProteinConversion: conversion,
                    now: now
                )
                guard let carbs = merge.carbs else { return nil }
                return (carbs, data: merge.meals)
            }
            guard changed else { return }

            // rows first: Home refreshes its meal totals on the carbHistory publish
            if let meals, meals.isNotEmpty {
                await mealRows.saveMeals(meals)
            }
            // newest -> oldest
            appCoordinator.setCarbHistory(carbs)
            appCoordinator.sendMealsChanged()
        }
    }

    private static let oldSplitsMigratedKey = "carbHistory.oldSplitsMigrated"

    /// Once: the carbs file of an older version, which split the downloads on every poll (see `migrateOldSplits`)
    /// Returns the Meals rows to write after it: the older version's download rows are stale, the removed copies' go
    private func migrateOldSplitsOnce() async -> MigratedMealRows? {
        guard !UserDefaults.standard.bool(forKey: Self.oldSplitsMigratedKey) else { return nil }
        let fpu = await FPUSettings(settingsManager.settings)
        let (migrated, carbs, rows) = await storage.maybeModifyWithData(
            file: carbsFile,
            as: CarbsEntry.self
        ) { stored -> ([CarbsEntry], data: MigratedMealRows)? in
            guard let carbs = BaseCarbsStorage.migrateOldSplits(stored, fpu: fpu, newID: { UUID().uuidString }) else {
                return nil
            }
            return (carbs, data: BaseCarbsStorage.migratedMealRows(before: stored, after: carbs))
        }
        if migrated {
            debug(.apsManager, "Carbs: the carb equivalents of the old Nightscout split replaced")
        }
        UserDefaults.standard.set(true, forKey: Self.oldSplitsMigratedKey)
        return rows ?? Self.migratedMealRows(before: carbs, after: carbs)
    }

    /// A meal entered on this phone (one entry): the carbs file gets it and its carb equivalents
    private func storeCarbs(_ entries: [CarbsEntry]) async {
        let file = carbsFile
        var uniqEvents: [CarbsEntry] = []

        let entries = entries.map { entry -> CarbsEntry in
            var entry = entry
            entry.createdAt = entry.createdAt.truncatedToSecond
            return entry
        }

        let fat = entries.last?.fat ?? 0
        let protein = entries.last?.protein ?? 0
        let creationDate = entries.last?.createdAt ?? Date.now.truncatedToSecond

        let settings = await settingsManager.settings

        // Fat/protein are stored with the meal below either way; the conversion into future carb
        // equivalents is its own setting (Settings → Fat and Protein).
        if fat > 0 || protein > 0, settings.fatProteinConversion {
            let futureCarbArray = Self.carbEquivalents(
                fat: fat,
                protein: protein,
                start: entries.last?.actualDate ?? Date(),
                createdAt: creationDate,
                fpu: FPUSettings(settings)
            ) { _ in UUID().uuidString }
            let now = Date()
            // Save the array
            if futureCarbArray.isNotEmpty {
                uniqEvents = await self.storage.appendAndModify(futureCarbArray, to: file, uniqBy: \.id) {
                    $0
                        .filter { $0.createdAt.addingTimeInterval(.hours(24)) > now }
                        .sorted { $0.createdAt > $1.createdAt }
                }
            }
        }
        // Store the actual (normal) carbs
        if let entry = entries.last {
            let onlyCarbs = CarbsEntry(
                id: entry.id ?? "",
                createdAt: creationDate,
                actualDate: entry.actualDate ?? entry.createdAt,
                carbs: entry.carbs,
                fat: fat,
                protein: protein, fiber: entry.fiber,
                note: entry.note,
                enteredBy: entry.enteredBy ?? "",
                isFPU: false,
                micronutrient: entry.micronutrient
            )

            let now = Date()
            uniqEvents = await self.storage.appendAndModify([onlyCarbs], to: file, uniqBy: \.id) {
                $0
                    .filter { $0.createdAt.addingTimeInterval(.hours(24)) > now }
                    .sorted { $0.createdAt > $1.createdAt }
            }
        }

        // newest -> oldest
        appCoordinator.setCarbHistory(uniqEvents)
    }

    func syncDate() -> Date {
        Date().subtractingTimeInterval(.hours(24))
    }

    func deleteCarbsAndFPUs(at date: Date) async {
        await serializer.run {
            await doDeleteCarbsAndFPUs(at: date)
        }
    }

    private func doDeleteCarbsAndFPUs(at date: Date, publish: Bool = true) async {
        let (allValues, deleted) = await storage.delete(file: carbsFile, as: CarbsEntry.self) {
            $0.createdAt == date
        }
        // newest -> oldest
        if let deleted {
            // rows first: Home refreshes its meal totals on the carbHistory publish
            let ids = Self.mealRowIDs(of: deleted)
            if ids.isNotEmpty {
                await mealRows.deleteMeals(ids: ids)
            }
            if publish {
                appCoordinator.setCarbHistory(allValues)
                // a replaced meal sends it once, after the new one is stored
                appCoordinator.sendMealsChanged()
            }
            appCoordinator.sendCarbDeleted(deleted)
        }
    }

    /// The ids of the Meals rows of these carbs entries: the meals' own (an FPU entry has no row, an entry without an id
    /// cannot be matched to one), each once
    static func mealRowIDs(of entries: [CarbsEntry]) -> [String] {
        var seen = Set<String>()
        return entries.compactMap { entry -> String? in
            guard entry.isFPU != true, let id = entry.id, !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
    }
}

// MARK: - Carb equivalents and the Nightscout download

/// The settings of the fat and protein split
struct FPUSettings: Sendable, Equatable {
    /// minutes between the carb equivalents
    let interval: Int
    /// the longest split, in hours
    let timeCap: Int
    let adjustment: Decimal
    /// minutes before the first carb equivalent
    let delay: Int
}

extension FPUSettings {
    init(_ settings: FreeAPSSettings) {
        self.init(
            interval: settings.minuteInterval,
            timeCap: settings.timeCap,
            adjustment: settings.individualAdjustmentFactor,
            delay: settings.delay
        )
    }
}

/// The Meals rows a migration of the carbs file changes
struct MigratedMealRows: Sendable {
    let save: [CarbsEntry]
    let delete: [String]
}

/// What a Nightscout download does to the carbs file
struct DownloadedCarbsMerge: Sendable {
    /// the carbs file after the download, nil when it is unchanged
    let carbs: [CarbsEntry]?
    /// the downloaded meals added or changed (for their Meals rows)
    let meals: [CarbsEntry]
}

extension BaseCarbsStorage {
    /// The carb equivalents of a meal's fat and protein, from `start` + the delay, `interval` minutes apart; `id` names
    /// the n-th one
    static func carbEquivalents(
        fat: Decimal,
        protein: Decimal,
        start: Date,
        createdAt: Date,
        fpu: FPUSettings,
        id: (Int) -> String
    ) -> [CarbsEntry] {
        let interval = fpu.interval // Interval between carbs
        let timeCap = fpu.timeCap // Max Duration
        let adjustment = fpu.adjustment
        let delay = fpu.delay // Tme before first future carb entry
        let kcal = protein * 4 + fat * 9
        let carbEquivalents = (kcal / 10) * adjustment
        let fpus = carbEquivalents / 10
        // Duration in hours used for extended boluses with Warsaw Method. Here used for total duration of the computed carb equivalents instead, excluding the configurable delay.
        var computedDuration = 0
        switch fpus {
        case ..<2:
            computedDuration = 3
        case 2 ..< 3:
            computedDuration = 4
        case 3 ..< 4:
            computedDuration = 5
        default:
            computedDuration = timeCap
        }
        // Size of each created carb equivalent if 60 minutes interval
        var equivalent: Decimal = carbEquivalents / Decimal(computedDuration)
        // Adjust for interval setting other than 60 minutes
        equivalent /= Decimal(60 / interval)
        // Round to 1 fraction digit
        equivalent = Decimal(round(Double(equivalent * 10)) / 10)
        // Round up to 1 or done to 0 as oref0 only accepts carbs >= 1
        equivalent = equivalent > IAPSconfig.minimumCarbEquivalent ? max(equivalent, 1) : 0
        // Number of equivalents
        var numberOfEquivalents = equivalent > 0 ? carbEquivalents / equivalent : 0
        // Only use delay in first loop
        var firstIndex = true
        // New date for each carb equivalent
        var useDate = start
        // Group and Identify all FPUs together
        // Create an array of all future carb equivalents.
        var futureCarbArray = [CarbsEntry]()
        while carbEquivalents > 0, numberOfEquivalents > 0 {
            if firstIndex {
                useDate = useDate.addingTimeInterval(.minutes(delay))
                firstIndex = false
            } else { useDate = useDate.addingTimeInterval(.minutes(interval)) }

            let eachCarbEntry = CarbsEntry(
                id: id(futureCarbArray.count), createdAt: createdAt, actualDate: useDate,
                carbs: equivalent, fat: 0, protein: 0, fiber: nil, note: nil,
                enteredBy: CarbsEntry.manual, isFPU: true
            )
            futureCarbArray.append(eachCarbEntry)
            numberOfEquivalents -= 1
        }
        return futureCarbArray
    }

    /// The ids of the carb equivalents of a downloaded meal start with this
    static func downloadedFPUPrefix(_ mealID: String) -> String {
        mealID + ".fpu."
    }

    /// iAPS's own meal coming back from Nightscout: entered here (a remote meal too), or uploaded with the id of a
    /// stored entry
    static func isOwnUpload(_ entry: CarbsEntry, storedIDs: Set<String>) -> Bool {
        if entry.isLocallyEntered || (entry.enteredBy?.contains(CarbsEntry.manual) ?? false) {
            return true
        }
        guard let uploadedID = entry.uploadedID, !uploadedID.isEmpty else { return false }
        return storedIDs.contains(uploadedID)
    }

    /// A downloaded meal as it is stored: its own time (to the second) as the meal time, fat and protein never nil
    static func storedDownload(_ entry: CarbsEntry, id: String) -> CarbsEntry {
        let createdAt = entry.createdAt.truncatedToSecond
        return CarbsEntry(
            id: id,
            createdAt: createdAt,
            actualDate: entry.actualDate?.truncatedToSecond ?? createdAt,
            carbs: entry.carbs,
            fat: entry.fat ?? 0,
            protein: entry.protein ?? 0,
            fiber: entry.fiber,
            note: entry.note,
            enteredBy: entry.enteredBy ?? "",
            isFPU: false,
            micronutrient: entry.micronutrient
        )
    }

    /// The carbs file after a Nightscout download (the last 24 h, again on every poll):
    /// - iAPS's own meals (`isOwnUpload`) are not imported again
    /// - a meal is stored once, by its Nightscout id (copies of it collapse); one edited on this phone keeps the local
    ///   version, and loses the download's carb equivalents
    /// - its carb equivalents come from its own fat and protein, from its own time: split when it arrives, and again
    ///   only when its fat, protein or time change (the ids are derived from the meal's, so a split replaces the last,
    ///   and nothing else: another meal's, of the same created-at, are never touched)
    /// - `fatProteinConversion` off (as for a meal entered here): a new or changed meal gets no carb equivalents, and a
    ///   changed one loses its old ones (as a meal edited here); an unchanged one keeps the ones it has
    /// `meals`: the meals added or changed (for their Meals rows)
    static func mergeDownloaded(
        _ fetched: [CarbsEntry],
        into stored: [CarbsEntry],
        fpu: FPUSettings,
        fatProteinConversion: Bool,
        now: Date
    ) -> DownloadedCarbsMerge {
        let cutoff = now.addingTimeInterval(.hours(-24))
        let storedIDs = Set(stored.compactMap(\.id).filter { !$0.isEmpty })
        var carbs = stored
        var meals: [CarbsEntry] = []
        var changed = false

        for downloaded in fetched {
            guard let id = downloaded.id, !id.isEmpty, !isOwnUpload(downloaded, storedIDs: storedIDs) else { continue }
            let meal = storedDownload(downloaded, id: id)
            guard meal.createdAt > cutoff else { continue }

            let prefix = downloadedFPUPrefix(id)
            let isOwnFPU = { (entry: CarbsEntry) -> Bool in
                entry.isFPU == true && (entry.id ?? "").hasPrefix(prefix)
            }
            let isParent = { (entry: CarbsEntry) -> Bool in
                entry.isFPU != true && entry.id == id
            }

            // edited on this phone: the local version wins, the download's copies and carb equivalents go
            if carbs.contains(where: { isParent($0) && $0.isLocallyEntered }) {
                let count = carbs.count
                carbs.removeAll { isOwnFPU($0) || (isParent($0) && !$0.isLocallyEntered) }
                changed = changed || carbs.count != count
                continue
            }

            // copies of one id (left by an older version's created-at merge): the first stays
            var parentIndex: Int?
            var collapsed = false
            for index in carbs.indices.reversed() where isParent(carbs[index]) {
                if let later = parentIndex {
                    carbs.remove(at: later)
                    collapsed = true
                }
                parentIndex = index
            }
            let parent = parentIndex.map { carbs[$0] }

            let equivalents = fatProteinConversion ? carbEquivalents(
                fat: meal.fat ?? 0,
                protein: meal.protein ?? 0,
                start: meal.actualDate ?? meal.createdAt,
                createdAt: meal.createdAt,
                fpu: fpu
            ) { prefix + String($0) } : []

            // the conversion off: an unchanged meal keeps its carb equivalents (copies collapsed or not)
            let split: Bool
            if let parent, !collapsed || !fatProteinConversion {
                split = !sameSplitSource(parent, meal) || (equivalents.isNotEmpty && !carbs.contains(where: isOwnFPU))
            } else {
                split = true
            }

            if let parentIndex {
                if collapsed || !sameDownload(carbs[parentIndex], meal) {
                    carbs[parentIndex] = meal
                    meals.append(meal)
                    changed = true
                }
            } else {
                carbs.append(meal)
                meals.append(meal)
                changed = true
            }
            if split {
                carbs.removeAll(where: isOwnFPU)
                carbs.append(contentsOf: equivalents)
                changed = true
            }
        }

        guard changed else { return DownloadedCarbsMerge(carbs: nil, meals: []) }
        let kept = carbs
            .filter { $0.createdAt.addingTimeInterval(.hours(24)) > now }
            .sorted { $0.createdAt > $1.createdAt }
        return DownloadedCarbsMerge(carbs: kept, meals: meals)
    }

    /// A Nightscout `_id` (an ObjectId: 24 hex digits), not an id given here
    static func isNightscoutID(_ id: String?) -> Bool {
        guard let id, id.count == 24 else { return false }
        return id.allSatisfy(\.isHexDigit)
    }

    /// Once, the carbs file of an older version, which split the downloads on every poll from "now" (with fresh ids,
    /// by the oldest download's fat and protein), and imported iAPS's remote meals back on every poll:
    /// Only duplication is repaired, never a split made under other settings than today's (that would change dosing):
    /// 1. a meal entered here with copies imported back (same created-at and carbs and source, a Nightscout id), or
    ///    with a pile of carb equivalents at its created-at (`isOneSplitShape` fails), loses the copies and all carb
    ///    equivalents of its created-at, and is split once again, from its own fat, protein and time (ids from
    ///    `newID`, as when entered). Two meals entered here of one created-at are left alone
    /// 2. a download loses its copies (of one id, the first stays). Its created-at's old carb equivalents (other ids
    ///    than the downloads' own): one split of the one download with fat or protein there is kept, as its own (the
    ///    ids renamed); a pile is replaced by each download's own split. Not when a meal entered here shares the
    ///    created-at: those carb equivalents can be its
    /// nil when there is nothing to change
    static func migrateOldSplits(_ stored: [CarbsEntry], fpu: FPUSettings, newID: () -> String) -> [CarbsEntry]? {
        var carbs = stored
        var changed = false
        let isMeal = { (entry: CarbsEntry) -> Bool in entry.isFPU != true }
        let isEnteredHere = { (entry: CarbsEntry) -> Bool in BaseCarbsStorage.isEnteredHere(entry) }
        /// split by this version from a download (never an old split)
        let isDownloadSplit = { (entry: CarbsEntry) -> Bool in (entry.id ?? "").contains(".fpu.") }
        let isOldFPU = { (entry: CarbsEntry, at: Date) -> Bool in
            entry.isFPU == true && entry.createdAt == at && !isDownloadSplit(entry)
        }

        // 1. the meals entered here
        let localTimes = Set(carbs.filter { isMeal($0) && isEnteredHere($0) }.map(\.createdAt))
        for at in localTimes {
            let group = carbs.filter { isMeal($0) && isEnteredHere($0) && $0.createdAt == at }
            guard let original = group.first(where: { !isNightscoutID($0.id) }) ?? group.first else { continue }
            // imported back: the same meal, or (a remote meal edited here) any remote one with a Nightscout id
            let isCopy = { (entry: CarbsEntry) -> Bool in
                guard isMeal(entry), entry.createdAt == at, entry.id != original.id, isNightscoutID(entry.id) else {
                    return false
                }
                return entry.enteredBy == CarbsEntry.remote
                    || (sameAmount(entry.carbs, original.carbs) && entry.enteredBy == original.enteredBy)
            }
            guard group.filter({ !isCopy($0) }).count == 1 else { continue }

            let copies = carbs.filter(isCopy)
            let fpus = carbs.filter { isOldFPU($0, at) }
            guard copies.isNotEmpty || !isOneSplitShape(fpus) else { continue }

            let split = carbEquivalents(
                fat: original.fat ?? 0,
                protein: original.protein ?? 0,
                start: original.actualDate ?? original.createdAt,
                createdAt: at,
                fpu: fpu
            ) { _ in newID() }
            carbs.removeAll { isCopy($0) || isOldFPU($0, at) }
            carbs.append(contentsOf: split)
            changed = true
        }

        // 2. the downloads
        let remainingLocalTimes = Set(carbs.filter { isMeal($0) && isEnteredHere($0) }.map(\.createdAt))
        var seen = Set<String>()
        var copyTimes = Set<Date>()
        carbs.removeAll { entry in
            guard isMeal(entry), !isEnteredHere(entry), let id = entry.id, !id.isEmpty else { return false }
            // the first of an id stays
            guard seen.insert(id).inserted else {
                copyTimes.insert(entry.createdAt)
                return true
            }
            return false
        }
        changed = changed || copyTimes.isNotEmpty

        let downloads = carbs.filter { isMeal($0) && !isEnteredHere($0) && !($0.id ?? "").isEmpty }
        let downloadTimes = Set(downloads.map(\.createdAt))
        for at in copyTimes.union(downloadTimes) where !remainingLocalTimes.contains(at) {
            let old = carbs.filter { isOldFPU($0, at) }
            let splitting = downloads.filter { download in
                download.createdAt == at && ((download.fat ?? 0) > 0 || (download.protein ?? 0) > 0)
            }
            if old.isNotEmpty, isOneSplitShape(old), splitting.count == 1, let id = splitting[0].id {
                // one split, of the one download it can be: kept as it is, as that download's
                let prefix = downloadedFPUPrefix(id)
                let adopted = sortedByTime(old).enumerated().map { index, entry in
                    CarbsEntry(
                        id: prefix + String(index), createdAt: entry.createdAt, actualDate: entry.actualDate,
                        carbs: entry.carbs, fat: entry.fat, protein: entry.protein, fiber: entry.fiber, note: entry.note,
                        enteredBy: entry.enteredBy, isFPU: true
                    )
                }
                carbs.removeAll { isOldFPU($0, at) || ($0.isFPU == true && ($0.id ?? "").hasPrefix(prefix)) }
                carbs.append(contentsOf: adopted)
                changed = true
                continue
            }

            let count = carbs.count
            carbs.removeAll { isOldFPU($0, at) }
            var added = false
            for download in downloads where download.createdAt == at {
                let prefix = downloadedFPUPrefix(download.id ?? "")
                let own = carbs.filter { $0.isFPU == true && ($0.id ?? "").hasPrefix(prefix) }
                guard own.isEmpty else { continue }
                let split = carbEquivalents(
                    fat: download.fat ?? 0,
                    protein: download.protein ?? 0,
                    start: download.actualDate ?? download.createdAt,
                    createdAt: at,
                    fpu: fpu
                ) { prefix + String($0) }
                carbs.append(contentsOf: split)
                added = added || split.isNotEmpty
            }
            changed = changed || added || carbs.count != count
        }

        guard changed else { return nil }
        return carbs.sorted { $0.createdAt > $1.createdAt }
    }

    /// Entered here (any source of this phone, a remote meal too), not downloaded
    static func isEnteredHere(_ entry: CarbsEntry) -> Bool {
        entry.isLocallyEntered || (entry.enteredBy?.contains(CarbsEntry.manual) ?? false)
    }

    /// The Meals rows after a migration: every download of the file in its stored shape (the older version's rows have
    /// the first poll's time, and the amounts from before an edit), and the rows of the meals it removed deleted
    static func migratedMealRows(before: [CarbsEntry], after: [CarbsEntry]) -> MigratedMealRows {
        let save = after
            .filter { $0.isFPU != true && !isEnteredHere($0) && !($0.id ?? "").isEmpty }
            .map { storedDownload($0, id: $0.id ?? "") }
        let kept = Set(after.filter { $0.isFPU != true }.compactMap(\.id))
        let removed = Set(before.filter { $0.isFPU != true }.compactMap(\.id)).filter { !$0.isEmpty && !kept.contains($0) }
        return MigratedMealRows(save: save, delete: removed.sorted())
    }

    /// These carb equivalents can be one split, under any settings: one amount, at distinct times one step apart (to
    /// the second). Not a pile of several splits (from several starts). None is not a pile either
    static func isOneSplitShape(_ fpus: [CarbsEntry]) -> Bool {
        guard let first = fpus.first else { return true }
        guard fpus.allSatisfy({ sameAmount($0.carbs, first.carbs) }) else { return false }
        let times = sortedByTime(fpus).map { ($0.actualDate ?? $0.createdAt).timeIntervalSince1970 }
        let steps = zip(times.dropFirst(), times).map { later, earlier in later - earlier }
        guard let step = steps.first else { return true }
        guard step >= 1 else { return false }
        return steps.allSatisfy { abs($0 - step) < 1 }
    }

    private static func sortedByTime(_ entries: [CarbsEntry]) -> [CarbsEntry] {
        entries.sorted { ($0.actualDate ?? $0.createdAt) < ($1.actualDate ?? $1.createdAt) }
    }

    /// The same split: the same fat, protein and time
    private static func sameSplitSource(_ lhs: CarbsEntry, _ rhs: CarbsEntry) -> Bool {
        sameAmount(lhs.fat, rhs.fat)
            && sameAmount(lhs.protein, rhs.protein)
            && lhs.createdAt == rhs.createdAt
            && (lhs.actualDate ?? lhs.createdAt) == (rhs.actualDate ?? rhs.createdAt)
    }

    /// The same stored download (`==` compares only the created-at)
    private static func sameDownload(_ lhs: CarbsEntry, _ rhs: CarbsEntry) -> Bool {
        sameSplitSource(lhs, rhs)
            && sameAmount(lhs.carbs, rhs.carbs)
            && sameAmount(lhs.fiber, rhs.fiber)
            && lhs.note == rhs.note
            && lhs.enteredBy == rhs.enteredBy
            && lhs.isFPU == rhs.isFPU
    }

    /// Equal to the milligram: a stored amount read back from the file may differ in the last digits from the
    /// download's (a careportal string)
    private static func sameAmount(_ lhs: Decimal?, _ rhs: Decimal?) -> Bool {
        (lhs ?? 0).rounded(to: 3) == (rhs ?? 0).rounded(to: 3)
    }
}
