import AVFAudio
import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose]) -> [BloodGlucose]
    func removeGlucose(ids: [String])
    /// retrieves raw glucose from storage - no smoothing
    func retrieveRaw() -> [BloodGlucose]
    /// retrieves glucose from storage
    /// if glucose smoothing is enabled in settings - applies the smoothing algorithm
    func retrieve() -> [BloodGlucose]
    /// retrieves glucose from storage
    /// if glucose smoothing is enabled in settings - applies the smoothing algorithm
    /// filters records by frequency - at most "1 per minute" or "1 per 5 minutes" (according to settings.allowOneMinuteGlucose)
    func retrieveFiltered() -> [BloodGlucose]
    func latestDate() -> Date?
    func filterFrequentGlucose(_ glucose: [BloodGlucose], interval: TimeInterval) -> [BloodGlucose]
    var alarm: GlucoseAlarm? { get }
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    private enum Config {
        static let filterTimeFiveMinutes: TimeInterval = 4.5 * 60
        static let filterTimeOneMinute: TimeInterval = 0.8 * 60
    }

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeGlucose(_ glucose: [BloodGlucose]) -> [BloodGlucose] {
        processQueue.sync {
            debug(.deviceManager, "start storage glucose")
            let file = OpenAPS.Monitor.glucose
            var stored: [BloodGlucose] = []
            self.storage.transaction { storage in
                let existing = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.reversed() ?? []
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

                storage.append(newRecords, to: file, uniqBy: \.dateString)

                let now = Date()
                let uniqEvents = storage.retrieve(file, as: [BloodGlucose].self)?
                    .filter { $0.dateString.addingTimeInterval(24.hours.timeInterval) > now }
                    .sorted { $0.dateString > $1.dateString } ?? []
                let newGlucoseData = Array(uniqEvents)

                // FileStorage
                storage.save(newGlucoseData, as: file)

                // Only log once
                debug(
                    .deviceManager,
                    "storeGlucose \(newRecords.count) new entries. Latest Glucose: \(String(describing: glucose.last?.glucose)) mg/Dl, date: \(String(describing: glucose.last?.dateString))."
                )

                stored = newGlucoseData

                DispatchQueue.main.async {
                    self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate(newGlucoseData.reversed())
                    }
                    self.broadcaster.notify(NewGlucoseObserver.self, on: .main) {
                        $0.newGlucoseStored(newRecords)
                    }
                }
            }

            // Do we have a sensor session start?
            if let sensorSessionStart = glucose.first(where: { $0.sessionStartDate != nil }) {
                debug(.deviceManager, "start storage cgmState")
                self.storage.transaction { storage in
                    let file = OpenAPS.Monitor.cgmState
                    var treatments = storage.retrieve(file, as: [NigtscoutTreatment].self) ?? []
                    var notes = ""
                    if let t = sensorSessionStart.transmitterID {
                        notes = t
                    }
                    if let a = sensorSessionStart.activationDate {
                        notes = "\(notes) activated on \(a)"
                    }

                    let treatment = NigtscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsSensorChange,
                        createdAt: sensorSessionStart.sessionStartDate,
                        enteredBy: NigtscoutTreatment.local,
                        bolus: nil,
                        insulin: nil,
                        notes: notes,
                        carbs: nil,
                        fat: nil,
                        protein: nil,
                        targetTop: nil,
                        targetBottom: nil
                    )
                    treatments.append(treatment)
                    debug(.deviceManager, "CGM sensor change \(String(describing: sensorSessionStart.sessionStartDate))")

                    // We have to keep quite a bit of history as sensors start only every 10 days.
                    storage.save(
                        treatments.filter
                            { $0.createdAt != nil && $0.createdAt!.addingTimeInterval(30.days.timeInterval) > Date() },
                        as: file
                    )
                }
            }
            return stored
        }
    }

    func removeGlucose(ids: [String]) {
        processQueue.sync {
            let file = OpenAPS.Monitor.glucose
            self.storage.transaction { storage in
                let bgInStorage = storage.retrieve(file, as: [BloodGlucose].self)
                let filteredBG = bgInStorage?.filter { !ids.contains($0.id) } ?? []
                guard bgInStorage != filteredBG else { return }
                storage.save(filteredBG, as: file)

                DispatchQueue.main.async {
                    self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate(filteredBG.reversed())
                    }
                }
            }
        }
    }

    func latestDate() -> Date? {
        guard let events = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self),
              let recent = events.first
        else {
            return nil
        }
        return recent.dateString
    }

    func retrieveRaw() -> [BloodGlucose] {
        storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.reversed() ?? []
    }

    func retrieve() -> [BloodGlucose] {
        // newest-to-oldest
        var retrieved = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.reversed() ?? []
        guard !retrieved.isEmpty else {
            return []
        }
        if settingsManager.settings.smoothGlucose {
            // smooth with 3 repeats
            for _ in 1 ... 3 {
                retrieved.smoothSavitzkyGolayQuaDratic(withFilterWidth: 3)
            }
        }
        return retrieved
    }

    func retrieveFiltered() -> [BloodGlucose] {
        let retrieved = retrieve() // smoothed already

        let minInterval = settingsManager.settings.allowOneMinuteGlucose ? Config.filterTimeOneMinute : Config
            .filterTimeFiveMinutes
        return filterFrequentGlucose(retrieved, interval: minInterval)
    }

    func filterFrequentGlucose(_ glucose: [BloodGlucose], interval: TimeInterval) -> [BloodGlucose] {
        // glucose is already sorted newest-to-oldest in retrieve
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

    var alarm: GlucoseAlarm? {
        guard let glucose = retrieveRaw().last, glucose.dateString.addingTimeInterval(20.minutes.timeInterval) > Date(),
              let glucoseValue = glucose.glucose else { return nil }

        if Decimal(glucoseValue) <= settingsManager.settings.lowGlucose {
            return .low
        }

        if Decimal(glucoseValue) >= settingsManager.settings.highGlucose {
            return .high
        }

        if let direction = glucose.direction, direction == .doubleDown || direction == .singleDown,
           Decimal(glucoseValue) < settingsManager.settings.highGlucose
        {
            return .descending
        }

        if let direction = glucose.direction, direction == .doubleUp || direction == .singleUp,
           Decimal(glucoseValue) > settingsManager.settings.lowGlucose,
           Decimal(glucoseValue) < settingsManager.settings.highGlucose
        {
            return .ascending
        }

        return nil
    }
}

protocol GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose])
}

protocol NewGlucoseObserver {
    func newGlucoseStored(_ glucose: [BloodGlucose])
}

enum GlucoseAlarm {
    case high
    case low
    case ascending
    case descending

    var displayName: String {
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
