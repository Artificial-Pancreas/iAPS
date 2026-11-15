import Foundation

enum NightscoutConversions {
    /// returns events converted to nightscout format, newest -> oldest
    static func treatments(fromPumpHistory events: [PumpHistoryEvent]) -> [NigtscoutTreatment] {
        guard !events.isEmpty else { return [] }

        // A temp basal is stored as a pair of events sharing a timestamp: a `.tempBasalDuration` under id `X` and
        // a `.tempBasal` (rate) under id `_X`. Pair them by id - their order in the history is not defined.
        let durations = Dictionary(
            events.filter { $0.type == .tempBasalDuration }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let temps = events.compactMap { event -> NigtscoutTreatment? in
            guard event.type == .tempBasal else { return nil }
            let id = event.id.hasPrefix("_") ? String(event.id.dropFirst()) : event.id
            guard let duration = durations[id], let durationMin = duration.durationMin else { return nil }
            return NigtscoutTreatment(
                duration: durationMin,
                rawDuration: duration,
                rawRate: event,
                absolute: event.rate,
                rate: event.rate,
                eventType: .nsTempBasal,
                createdAt: event.timestamp.truncatedToSecond,
                enteredBy: NigtscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
        }

        let bolusesAndCarbs = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .bolus:
                let eventType = determineBolusEventType(for: event)
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: eventType,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: event.amount,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .journalCarbs:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: Decimal(event.carbInput ?? 0),
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil,
                    creation_date: event.timestamp
                )
            default: return nil
            }
        }

        // A prime is no Site Change (Loop and Trio upload none for it): the Site Changes come from the pump's change
        // events (`PumpChangeRecorder`). The ones uploaded from primes before stay in Nightscout (`KeepingSink`).
        let misc = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .rewind:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsInsulinChange,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .pumpAlarm:
                return NigtscoutTreatment(
                    duration: 30, // minutes
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsAnnouncement,
                    createdAt: event.timestamp.truncatedToSecond,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: "Alarm \(String(describing: event.note)) \(event.type)",
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            default: return nil
            }
        }

        return (
            bolusesAndCarbs +
                temps +
                misc
        ).sorted { $0.createdAt > $1.createdAt }
    }

    private static func determineBolusEventType(for event: PumpHistoryEvent) -> EventType {
        if event.isSMB ?? false {
            return .smb
        }
        if event.isExternal ?? false {
            return .isExternal
        }
        return event.type
    }

    /// returns events converted to nightscout format, newest -> oldest
    static func treatments(fromCarbHistory events: [CarbsEntry]) -> [NigtscoutTreatment] {
        let eventsManual = events.filter(\.isSyncableMeal)
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.actualDate?.truncatedToSecond ?? .distantPast,
                enteredBy: $0.enteredBy ?? CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                carbs: $0.carbs,
                fat: $0.fat,
                protein: $0.protein,
                foodType: $0.note,
                targetTop: nil,
                targetBottom: nil,
                id: $0.id,
                fpuID: nil,
                creation_date: $0.createdAt
            )
        }
        return treatments.sorted { $0.createdAt > $1.createdAt }
    }

    /// returns temp targets converted to nightscout format, newest -> oldest
    static func treatments(fromTempTargets events: [TempTarget]) -> [NigtscoutTreatment] {
        let eventsManual = events.filter { $0.enteredBy == TempTarget.manual }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: $0.duration,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsTempTarget,
                createdAt: $0.createdAt.truncatedToSecond,
                enteredBy: TempTarget.manual,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                targetTop: $0.targetTop,
                targetBottom: $0.targetBottom
            )
        }
        return treatments.sorted { $0.createdAt > $1.createdAt }
    }

    /// A pump change as Loop uploads it (`PersistedPumpEvent.treatment`): a "Site Change" at the event's date, the
    /// driver's title as the notes (`created_at` to the second, as iAPS's other treatments; enteredBy "iAPS").
    static func siteChangeTreatment(_ change: PumpChangeRecorder.Change) -> NigtscoutTreatment {
        NigtscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .nsSiteChange,
            createdAt: change.date.truncatedToSecond,
            enteredBy: NigtscoutTreatment.local,
            bolus: nil,
            insulin: nil,
            notes: change.title,
            carbs: nil,
            fat: nil,
            protein: nil,
            targetTop: nil,
            targetBottom: nil
        )
    }
}

/// The pump drivers' change events (`pumpLifecycleEvents`) kept for the Nightscout "Site Change" upload, the way Loop
/// and Trio upload them: one per pod, patch or infusion set put in, at the event's date
/// (`NightscoutConversions.siteChangeTreatment`). The log is `Monitor/pump-changes.json`, `retention` long; the upload
/// reads it.
///
/// - **The pump sessions' rule** (`PumpSessionRules.change`): a pod's or patch's plugin changes with `.pump` (an
///   `.infusionSet` of it is none), a tube pump's with either; a `.reservoir` is none. An event within
///   `PumpSessionRules.dedupWindow` (2 min for a pod or patch, 15 min for a set) of a recorded change of the plugin is
///   that change: a re-send (Minimed's fixed prime comes again with every fetch, 35 min back, and after a relaunch;
///   Dana's boundary record) or the same set primed again (Dana). The log persists, so a relaunch records nothing again.
/// - **Only changes after the update.** `start()` begins the log (`since`) at the first launch running this, events or
///   not: an event dated before it (a re-send of an earlier change) is not recorded. Before the update the pod-age sync
///   and the primes uploaded those changes.
/// - Every pump iAPS ships sends these events (OmnipodKit, MedtrumKit, DanaKit, MinimedKit). A driver that sends none
///   gets no Site Change: there is no fallback.
/// - It records while the uploads are off too: turned on within `retention`, they upload. Uploads off or offline for
///   longer than `retention` lose a change, as for `cgmState`.
/// - The file is a one-element list: `FileStorage.maybeModifyWithData`, which reads, changes and saves it in one step,
///   works on lists.
actor PumpChangeRecorder {
    struct Change: Codable, Sendable, Equatable {
        let plugin: String
        /// `PumpLifecycleEvent.Component`'s raw value
        let component: String
        /// the event's, to the second
        let date: Date
        let title: String?
    }

    struct Log: JSON, Equatable {
        /// an event dated before it is not recorded
        var since: Date
        /// oldest first
        var changes: [Change]
    }

    static let retention: TimeInterval = .days(15)

    private let storage: FileStorage
    private let now: @Sendable() -> Date
    /// the log's start when there is none, to the second (a JSON round trip drifts sub-second dates)
    private let launch: Date

    init(storage: FileStorage, now: @escaping @Sendable() -> Date = { Date() }) {
        self.storage = storage
        self.now = now
        launch = now().truncatedToSecond
    }

    /// Begins the log at this launch when there is none (`NightscoutUploads.start`).
    func start() async {
        let launch = self.launch
        let file = OpenAPS.Monitor.pumpChanges
        if await storage.retrieveRaw(file) != nil, await storage.retrieve(file, as: [Log].self) == nil {
            warning(.nightscout, "Site Changes: \(file) can't be read, its log restarts at \(launch)")
        }
        await storage.maybeModify(file: OpenAPS.Monitor.pumpChanges, as: Log.self) { (logs: [Log]) -> [Log]? in
            logs.isEmpty ? [Log(since: launch, changes: [])] : nil
        }
    }

    /// Records the events' changes not recorded yet; returns whether it recorded any.
    func note(_ events: [PumpLifecycleEvent]) async -> Bool {
        let launch = self.launch
        let cutoff = now().addingTimeInterval(-Self.retention)
        let (_, _, recorded) = await storage
            .maybeModifyWithData(file: OpenAPS.Monitor.pumpChanges, as: Log.self) { (logs: [Log]) -> ([Log], data: [Change])? in
                if logs.isEmpty {
                    debug(.nightscout, "Site Changes: no log, it restarts at \(launch)")
                }
                var log = logs.first ?? Log(since: launch, changes: [])
                let recorded = Self.changes(events, notIn: log, cutoff: cutoff)
                guard recorded.isNotEmpty || logs.isEmpty else { return nil }
                log.changes = (log.changes + recorded).filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
                return ([log], data: recorded)
            }
        for change in recorded ?? [] {
            debug(.nightscout, "Site Change recorded: \(change.plugin) \(change.component) change at \(change.date)")
        }
        return recorded?.isNotEmpty == true
    }

    /// The events' changes the log doesn't have, oldest first (see the type's doc). An event before the log's start or
    /// the retention's (`cutoff`: the log prunes the changes before it) is none.
    static func changes(_ events: [PumpLifecycleEvent], notIn log: Log, cutoff: Date) -> [Change] {
        var known = log.changes
        var recorded: [Change] = []
        let from = Swift.max(log.since, cutoff)
        for event in events.sorted(by: { $0.date < $1.date }) where event.date >= from {
            let site = !PumpSessionRules.isPodOrPatch(event.plugin)
            switch event.component {
            case .reservoir: continue
            case .infusionSet where !site: continue
            case .infusionSet,
                 .pump: break
            }
            let window = PumpSessionRules.dedupWindow(site: site)
            guard !known.contains(where: { change in
                change.plugin == event.plugin && abs(change.date.timeIntervalSince(event.date)) <= window
            }) else { continue }
            let change = Change(
                plugin: event.plugin,
                component: event.component.rawValue,
                date: event.date.truncatedToSecond,
                title: event.title
            )
            known.append(change)
            recorded.append(change)
        }
        return recorded
    }

    /// The Site Changes to upload: the log's, within `retention`.
    func currentRecords() async -> [NigtscoutTreatment] {
        let cutoff = now().addingTimeInterval(-Self.retention)
        let log = await storage.retrieve(OpenAPS.Monitor.pumpChanges, as: [Log].self)?.first
        return (log?.changes ?? []).filter { $0.date >= cutoff }.map(NightscoutConversions.siteChangeTreatment)
    }
}

/// Maintains the local log of CGM sensor-start events (`Monitor/cgm-state.json`):
/// dedupes session starts and serves the current records for upload.
actor CgmStateRecorder {
    private let storage: FileStorage
    private var lastSeenStart: Date?

    init(storage: FileStorage) {
        self.storage = storage
    }

    /// records a new sensor start if the status carries one; returns whether the log changed
    func noteStatus(_ cgmStatus: CgmDisplayStatus?) async -> Bool {
        guard let sessionStartDate = cgmStatus?.sessionStartDate,
              abs(sessionStartDate.timeIntervalSince(lastSeenStart ?? .distantPast)) > BloodGlucose.sessionTolerance
        else { return false }
        lastSeenStart = sessionStartDate
        return await recordSensorStartIfNeeded(sessionStartDate)
    }

    func currentRecords() async -> [NigtscoutTreatment] {
        let (_, cgmState) = await storage
            .maybeModify(file: OpenAPS.Monitor.cgmState, as: NigtscoutTreatment.self) { cgmState in
                // filter older cgm entries on read
                let daysAgo30 = Date.now.subtractingTimeInterval(.days(30))
                let last30days = cgmState.filter { $0.createdAt >= daysAgo30 }
                if last30days.count == cgmState.count {
                    return nil // do not modify
                }
                return last30days // save with older-than-30-days entries removed
            }

        return cgmState
    }

    private func recordSensorStartIfNeeded(_ sessionStartDate: Date) async -> Bool {
        let (didModify, _) = await storage
            .maybeModify(file: OpenAPS.Monitor.cgmState, as: NigtscoutTreatment.self) { inStorage in
                // For Dexcom, each glucose event contains the sessionStartDate (which contains the correct timestamp of the latest sensor start)
                // We only need to send the "Sensor Start" event once per change.
                // This guard ensures we send a new "Sensor Start" event to NS only if the previously sent event happened
                // more than `sessionTolerance` before this one.
                //
                // Without it, sources that jitter the sessionStartDate flood NS with duplicate Session Start events.
                // See: https://github.com/Artificial-Pancreas/iAPS/issues/1806
                if inStorage
                    .contains(where: { abs($0.createdAt.timeIntervalSince(sessionStartDate)) < BloodGlucose.sessionTolerance })
                {
                    return nil // do not modify
                }

                debug(.deviceManager, "CGM sensor change \(sessionStartDate)")

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
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )

                var treatments = inStorage
                treatments.append(treatment)

                // We have to keep quite a bit of history as sensors start only every 10 days.
                let daysAgo30 = Date.now.subtractingTimeInterval(.days(30))
                return treatments
                    .filter { $0.createdAt >= daysAgo30 }
                    .sorted { $0.createdAt > $1.createdAt }
            }
        return didModify
    }
}
