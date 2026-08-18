import AVFAudio
import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage: Sendable {
    /// returns nil when no new records were recorded
    func storeGlucose(_ glucose: [BloodGlucose]) async -> [BloodGlucose]?

    func removeGlucose(ids: [String]) async

    func latestDate() async -> Date?

    func saveRawJSON(_ raw: RawJSON) async throws
}

actor BaseGlucoseStorage: GlucoseStorage, AppService, LifetimeOwner {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    // newest -> oldest
    private var cachedGlucose: [BloodGlucose] = []

    let lifetime = CancelBag()

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called at the start of the app
    func start() async {
        setCachedGlucose(await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self) ?? [])

        // both transforms must be explicitly @Sendable: plain closure literals formed here would be
        // inferred isolated to this actor, and Combine runs them synchronously on whatever executor
        // sends into the subject (SettingsManager's). Same fix as in BaseStateModel.
        let extract: @Sendable(FreeAPSSettings) -> (Bool, Bool, Bool) = {
            ($0.smoothGlucose, $0.orefOneMinuteGlucose, $0.allowOneMinuteLoop)
        }
        let isDuplicate: @Sendable((Bool, Bool, Bool), (Bool, Bool, Bool)) -> Bool = { $0 == $1 }

        observe(
            appCoordinator.settings
                .map(extract)
                .removeDuplicates(by: isDuplicate)
                .dropFirst()
        ) { me, _ in
            await me.updateAppCoordinator() // recompute smoothed / filtered glucose and the gaps
        }

        // an ongoing gap keeps growing while no readings arrive, and nothing else republishes it
        observe(appCoordinator.appBecomeActiveEvents) { me, _ in
            await me.publishGlucoseGaps()
        }
    }

    func storeGlucose(_ glucose: [BloodGlucose]) async -> [BloodGlucose]? {
        guard glucose.isNotEmpty else { return nil }
        debug(.deviceManager, "start storage glucose")

        let (didModify, stored, data: newRecords) = await storage
            .maybeModifyWithData(
                file: OpenAPS.Monitor.glucose,
                as: BloodGlucose.self
            ) { existing -> ([BloodGlucose], data: [BloodGlucose])? in
                var existingDates = existing.filter { $0.type == GlucoseType.sgv.rawValue }.map(\.dateString)
                var newRecords: [BloodGlucose] = []
                newRecords.reserveCapacity(glucose.count)
                for bg in glucose {
                    if bg.type == GlucoseType.sgv.rawValue {
                        if existingDates.contains(where: { abs($0.timeIntervalSince(bg.dateString)) <= 45 })
                        {
                            // skip if we already have a record within +/- 45 seconds
                            continue
                        }
                        newRecords.append(bg)
                        existingDates.append(bg.dateString)
                    } else {
                        newRecords.append(bg)
                    }
                }
                guard newRecords.isNotEmpty else {
                    return nil // do not modify
                }

                // TODO: temporary until further storage refactoring
                let appended = BaseFileStorage.doAppend(newRecords, existingValues: existing, uniqBy: \.dateString)

                let now = Date()
                let filtered = appended
                    .filter { $0.dateString.addingTimeInterval(.hours(24)) > now }
                    .sorted { $0.dateString > $1.dateString }
                return (filtered, data: newRecords)
            }

        guard didModify, let newRecords else { return nil }

        setCachedGlucose(stored)
        appCoordinator.sendNewGlucoseRecords(newRecords)

        // Only log once
        debug(
            .deviceManager,
            "storeGlucose \(newRecords.count) new entries. Latest Glucose: \(String(describing: glucose.last?.glucose)) mg/Dl, date: \(String(describing: glucose.last?.dateString))."
        )

        return stored
    }

    func removeGlucose(ids: [String]) async {
        let file = OpenAPS.Monitor.glucose
        let (bgInStorage, deleted) = await self.storage.delete(file: file, as: BloodGlucose.self) {
            ids.contains($0.id)
        }
        if let deleted {
            setCachedGlucose(bgInStorage)
            appCoordinator.sendGlucoseDeleted(deleted)
        }
    }

    func latestDate() async -> Date? {
        // file is stored newest -> oldest, so the first record is the most recent
        cachedGlucose.first?.dateString
    }

    func saveRawJSON(_ raw: RawJSON) async throws {
        try await storage.save(raw: raw, as: OpenAPS.Monitor.glucose, decodingInto: [BloodGlucose].self)
        await resetCache()
    }

    /// clears the in-memory cache, forcing a re-read from storage
    private func resetCache() async {
        setCachedGlucose(await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self) ?? [])
    }

    private func setCachedGlucose(_ glucose: [BloodGlucose]) {
        cachedGlucose = glucose
        updateAppCoordinator()
    }

    private func getAlarm() -> GlucoseAlarm? {
        guard let glucose = cachedGlucose.first, glucose.dateString.addingTimeInterval(.minutes(20)) > Date()
        else { return nil }

        let glucoseValue = glucose.glucose

        let settings = appCoordinator.settings.value

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

    private static let filterIntervalFiveMinutes: TimeInterval = .minutes(4.5)
    private static let filterIntervalOneMinute: TimeInterval = .minutes(0.8)
    private static let numberOfSavitzkyGolayPasses = 3

    private func updateAppCoordinator() {
        var smoothed: [BloodGlucose] = cachedGlucose
        if appCoordinator.settings.value.smoothGlucose {
            if smoothed.isNotEmpty {
                // reverse to oldest->newest
                smoothed.reverse()
                for _ in 1 ... Self.numberOfSavitzkyGolayPasses {
                    smoothed.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
                }
                // reverse back to newest->oldest
                smoothed.reverse()
            }
        }

        let minInterval = appCoordinator.settings.value.orefOneMinuteGlucose ? Self.filterIntervalOneMinute : Self
            .filterIntervalFiveMinutes
        let frequencyFiltered = FrequentGlucoseFiltering.filterFrequentGlucose(smoothed, interval: minInterval)

        // push alarm must happen before setGlucoseHistory
        appCoordinator.setGlucoseAlarm(getAlarm())
        // newest -> oldest
        appCoordinator.setGlucoseHistory(raw: cachedGlucose, smoothed: smoothed, frequencyFiltered: frequencyFiltered)

        publishGlucoseGaps()
    }

    private func publishGlucoseGaps() {
        // detect() returns oldest -> newest
        let gaps: [GlucoseGap] = GlucoseGap.detect(
            in: cachedGlucose,
            allowOneMinuteLoop: appCoordinator.settings.value.allowOneMinuteLoop
        ).reversed()

        guard gaps != appCoordinator.glucoseGaps.value else { return }

        appCoordinator.setGlucoseGaps(gaps)
    }
}

enum FrequentGlucoseFiltering {
    /// glucose must be newest -> oldest
    static func filterFrequentGlucose(_ glucose: [BloodGlucose], interval: TimeInterval) -> [BloodGlucose] {
        guard let latest = glucose.first else { return [] }

        var lastDate = latest.dateString
        // always keep the latest
        var filtered: [BloodGlucose] = [latest]

        for entry in glucose.dropFirst() {
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
