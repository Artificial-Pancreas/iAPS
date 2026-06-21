import AVFAudio
import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage: Sendable {
    func storeGlucose(_ glucose: [BloodGlucose]) async -> [BloodGlucose]
    func removeGlucose(ids: [String]) async
    /// retrieves raw glucose from storage - no smoothing
    func retrieveRaw() async -> [BloodGlucose]
    /// retrieves glucose from storage
    /// if glucose smoothing is enabled in settings - applies the smoothing algorithm
    func retrieve() async -> [BloodGlucose]
    /// retrieves glucose from storage
    /// if glucose smoothing is enabled in settings - applies the smoothing algorithm
    /// filters records by frequency - at most "1 per minute" or "1 per 5 minutes" (according to settings.allowOneMinuteGlucose)
    func retrieveFiltered() async -> [BloodGlucose]
    func latestDate() async -> Date?
    func getAlarm() async -> GlucoseAlarm?
}

actor BaseGlucoseStorage: GlucoseStorage, AppService {
    private let storage: FileStorage
    private let settingsManager: SettingsManager
    private let appCoordinator: AppCoordinator

    private enum Config {
        static let filterTimeFiveMinutes: TimeInterval = 4.5 * 60
        static let filterTimeOneMinute: TimeInterval = 0.8 * 60
    }

    init(
        storage: FileStorage,
        settingsManager: SettingsManager,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.settingsManager = settingsManager
        self.appCoordinator = appCoordinator
    }

    // this is called at the start of the app
    func start() async {
        // TODO: file is stored newest -> oldest, retrieveRaw reverses it, we reverse again to get back to newest -> oldest
        appCoordinator.setGlucoseHistory(await retrieveRaw().reversed())
    }

    func storeGlucose(_ glucose: [BloodGlucose]) async -> [BloodGlucose] {
        debug(.deviceManager, "start storage glucose")
        let file = OpenAPS.Monitor.glucose
        var stored: [BloodGlucose] = []

        let existing = await storage.retrieve(file, as: [BloodGlucose].self)?.reversed() ?? []
        var existingDates = existing.map(\.dateString)
        var newRecords: [BloodGlucose] = []
        newRecords.reserveCapacity(glucose.count)
        for bg in glucose {
            if existingDates.contains(where: { abs($0.timeIntervalSince(bg.dateString)) <= 45 }) {
                // skip if we already have a record within +/- 45 seconds
                continue
            }
            newRecords.append(bg)
            existingDates.append(bg.dateString)
        }

        // TODO: temporary until further storage refactoring
        let appended = BaseFileStorage.doAppend(newRecords, existingValues: existing, uniqBy: \.dateString)

        let now = Date()
        let uniqEvents = appended
            .filter { $0.dateString.addingTimeInterval(24.hours.timeInterval) > now }
            .sorted { $0.dateString > $1.dateString }
        let newGlucoseData = Array(uniqEvents)

        // FileStorage
        await storage.save(newGlucoseData, as: file)

        // Only log once
        debug(
            .deviceManager,
            "storeGlucose \(newRecords.count) new entries. Latest Glucose: \(String(describing: glucose.last?.glucose)) mg/Dl, date: \(String(describing: glucose.last?.dateString))."
        )

        stored = newGlucoseData

        // newest -> oldest
        appCoordinator.setGlucoseHistory(newGlucoseData)

        appCoordinator.newGlucoseRecords.send(newRecords)

        return stored
    }

    func removeGlucose(ids: [String]) async {
        let file = OpenAPS.Monitor.glucose
        let (bgInStorage, deleted) = await self.storage.delete(file: file, as: BloodGlucose.self) {
            ids.contains($0.id)
        }
        if let deleted {
            // newest -> oldest
            appCoordinator.setGlucoseHistory(bgInStorage)
            appCoordinator.sendGlucoseDeleted(deleted)
        }
    }

    func latestDate() async -> Date? {
        guard let events = await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self),
              let recent = events.first
        else {
            return nil
        }
        return recent.dateString
    }

    func retrieveRaw() async -> [BloodGlucose] {
        await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.reversed() ?? []
    }

    func retrieve() async -> [BloodGlucose] {
        // oldest-to-newest (file is stored newest-to-oldest, reversed here)
        var retrieved = await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.reversed() ?? []
        guard !retrieved.isEmpty else {
            return []
        }
        let settings = await settingsManager.settings
        if settings.smoothGlucose {
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                retrieved.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
        }
        return retrieved
    }

    func retrieveFiltered() async -> [BloodGlucose] {
        let retrieved = await retrieve() // smoothed already
        let settings = await settingsManager.settings

        let minInterval = settings.allowOneMinuteGlucose ? Config.filterTimeOneMinute : Config
            .filterTimeFiveMinutes
        return FrequentGlucoseFiltering.filterFrequentGlucose(retrieved, interval: minInterval)
    }

    func getAlarm() async -> GlucoseAlarm? {
        guard let glucose = await retrieveRaw().last, glucose.dateString.addingTimeInterval(20.minutes.timeInterval) > Date(),
              let glucoseValue = glucose.glucose else { return nil }

        let settings = await settingsManager.settings

        if Decimal(glucoseValue) <= settings.lowGlucose {
            return .low
        }

        if Decimal(glucoseValue) >= settings.highGlucose {
            return .high
        }

        if let direction = glucose.direction, direction == .doubleDown || direction == .singleDown,
           Decimal(glucoseValue) < settings.highGlucose
        {
            return .descending
        }

        if let direction = glucose.direction, direction == .doubleUp || direction == .singleUp,
           Decimal(glucoseValue) > settings.lowGlucose,
           Decimal(glucoseValue) < settings.highGlucose
        {
            return .ascending
        }

        return nil
    }
}

enum FrequentGlucoseFiltering {
    static func filterFrequentGlucose(_ glucose: [BloodGlucose], interval: TimeInterval) -> [BloodGlucose] {
        // glucose is oldest-to-newest from retrieve; re-sort newest-to-oldest for filtering
        let sorted = glucose.sorted { $0.date > $1.date }
        guard let latest = sorted.first else { return [] }

        var lastDate = latest.dateString
        // always keep the latest
        var filtered: [BloodGlucose] = [latest]

        for entry in sorted.dropFirst() {
            if lastDate.timeIntervalSince(entry.dateString) >= interval {
                filtered.append(entry)
                lastDate = entry.dateString
            }
        }

        return filtered
    }
}

enum GlucoseAlarm {
    case high
    case low
    case ascending
    case descending

    var displayName: String {
        // TODO: LOWALERT and HIGHALERT are swapped
        switch self {
        case .high:
            return NSLocalizedString("LOWALERT!", comment: "LOWALERT!")
        case .low:
            return NSLocalizedString("HIGHALERT!", comment: "HIGHALERT!")
        case .ascending:
            return NSLocalizedString("RAPIDLY ASCENDING GLUCOSE!", comment: "RAPIDLY ASCENDING GLUCOSE!")
        case .descending:
            return NSLocalizedString("RAPIDLY DESCENDING GLUCOSE!", comment: "RAPIDLY DESCENDING GLUCOSE!")
        }
    }
}
