import AVFAudio
import CoreData
import Foundation
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose])
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
    func nightscoutGlucoseNotUploaded() -> [BloodGlucose]
    func nightscoutCGMStateNotUploaded() -> [NigtscoutTreatment]
    func nightscoutManualGlucoseNotUploaded() -> [NigtscoutTreatment]
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

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.maximumFractionDigits = 1
        }
        formatter.decimalSeparator = "."
        return formatter
    }

    func storeGlucose(_ glucose: [BloodGlucose]) {
        processQueue.sync {
            debug(.deviceManager, "start storage glucose")
            let file = OpenAPS.Monitor.glucose
            self.storage.transaction { storage in
                storage.append(glucose, to: file, uniqByProj: { $0.dateRoundedTo1Second })

                let uniqEvents = storage.retrieve(file, as: [BloodGlucose].self)?
                    .filter { $0.dateString.addingTimeInterval(24.hours.timeInterval) > Date() }
                    .sorted { $0.dateString > $1.dateString } ?? []
                let glucose = Array(uniqEvents)
                storage.save(glucose, as: file)

                DispatchQueue.main.async {
                    self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate(glucose.reversed())
                    }
                }
            }

            debug(.deviceManager, "start storage cgmState")
            self.storage.transaction { storage in
                let file = OpenAPS.Monitor.cgmState
                var treatments = storage.retrieve(file, as: [NigtscoutTreatment].self) ?? []
                var updated = false
                for x in glucose {
                    debug(.deviceManager, "storeGlucose \(x)")
                    guard let sessionStartDate = x.sessionStartDate else {
                        continue
                    }
                    if let lastTreatment = treatments.last,
                       let createdAt = lastTreatment.createdAt,
                       // When a new Dexcom sensor is started, it produces multiple consequetive
                       // startDates. Disambiguate them by only allowing a session start per minute.
                       abs(createdAt.timeIntervalSince(sessionStartDate)) < TimeInterval(60)
                    {
                        continue
                    }
                    var notes = ""
                    if let t = x.transmitterID {
                        notes = t
                    }
                    if let a = x.activationDate {
                        notes = "\(notes) activated on \(a)"
                    }
                    let treatment = NigtscoutTreatment(
                        duration: nil,
                        rawDuration: nil,
                        rawRate: nil,
                        absolute: nil,
                        rate: nil,
                        eventType: .nsSensorChange,
                        createdAt: sessionStartDate,
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
                    debug(.deviceManager, "CGM sensor change \(treatment)")
                    treatments.append(treatment)
                    updated = true
                }
                if updated {
                    // We have to keep quite a bit of history as sensors start only every 10 days.
                    storage.save(
                        treatments.filter
                            { $0.createdAt != nil && $0.createdAt!.addingTimeInterval(30.days.timeInterval) > Date() },
                        as: file
                    )
                }
            }
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

    private func filterFrequentGlucose(_ glucose: [BloodGlucose], interval: TimeInterval) -> [BloodGlucose] {
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

    func nightscoutGlucoseNotUploaded() -> [BloodGlucose] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? []
        let recentGlucose = retrieveRaw()

        return Array(Set(recentGlucose).subtracting(Set(uploaded)))
    }

    func nightscoutCGMStateNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedCGMState, as: [NigtscoutTreatment].self) ?? []
        let recent = storage.retrieve(OpenAPS.Monitor.cgmState, as: [NigtscoutTreatment].self) ?? []
        return Array(Set(recent).subtracting(Set(uploaded)))
    }

    func nightscoutManualGlucoseNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = (storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? [])
            .filter({ $0.type == GlucoseType.manual.rawValue })
        let recent = retrieveRaw().filter({ $0.type == GlucoseType.manual.rawValue })
        let filtered = Array(Set(recent).subtracting(Set(uploaded)))
        let manualReadings = filtered.map { item -> NigtscoutTreatment in
            NigtscoutTreatment(
                duration: nil, rawDuration: nil, rawRate: nil, absolute: nil, rate: nil, eventType: .capillaryGlucose,
                createdAt: item.dateString, enteredBy: "iAPS", bolus: nil, insulin: nil, notes: "iAPS User", carbs: nil,
                fat: nil,
                protein: nil, foodType: nil, targetTop: nil, targetBottom: nil, glucoseType: "Manual",
                glucose: settingsManager.settings
                    .units == .mgdL ? (glucoseFormatter.string(from: Int(item.glucose ?? 100) as NSNumber) ?? "")
                    : (glucoseFormatter.string(from: Decimal(item.glucose ?? 100).asMmolL as NSNumber) ?? ""),
                units: settingsManager.settings.units == .mmolL ? "mmol" : "mg/dl"
            )
        }
        return manualReadings
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
