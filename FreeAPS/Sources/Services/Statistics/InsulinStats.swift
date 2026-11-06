import Foundation

/// What a `PumpEvent` row is (its `kind`). Earlier builds also wrote coverage rows (kind 9): no case, so a row of
/// theirs maps to no record, and the store's prune deletes it.
enum PumpEventKind: Int16, Sendable, Hashable, CaseIterable {
    case bolus = 0
    case tempBasal = 1
    case suspend = 2
    case resume = 3
}

/// Where a `PumpEvent` row came from (its `source`).
enum PumpEventSource: Int16, Sendable, Hashable {
    /// the live mirror of the pump history file
    case pump = 0
    /// the Nightscout backfill
    case nightscout = 1
}

/// What `CoreDataStorage.fetchCoverage` reads: a stretch where "no temp" means the scheduled basal (a pump session's
/// covered time, `PumpSessionValue.covered`), or a piece of the pump's local time (`isCovered == false`).
struct CoveredInterval: Sendable, Equatable {
    let interval: DateInterval
    /// `pump`: a heartbeat or the seed covered it, or the pump's local time; `nightscout`: the Nightscout evidence (a
    /// Nightscout session, or a pump session's prefix before its `localStart`)
    let source: PumpEventSource
    /// false: a piece of the pump's local time (`PumpSessionRules.localTime`, both ends included, zero-length ones too)
    /// that fills nothing by itself: a session's gaps, the pump's dose rows before the first session. The union of the
    /// `pump` entries is the local time, where a Nightscout event is the pump's double (`InsulinStatsEngine.usableEvents`)
    var isCovered = true
}

/// A `PumpEvent` row as a value: no managed object leaves its context.
struct PumpEventRecord: Sendable, Equatable {
    /// truncated to the second (by the mapping, not only by `PumpHistoryEvent.init`: decoded events skip it)
    var date: Date
    var kind: PumpEventKind
    var source: PumpEventSource
    /// bolus: the amount (programmed while mutable, delivered once final). tempBasal: the delivered units, or -1 while
    /// not delivered/final. Otherwise 0.
    var units: Double = 0
    /// tempBasal: U/h
    var rate: Double = 0
    /// tempBasal: the pair's `durationMin` as stored (pump rows carry the file's +0.1). bolus: the delivery time.
    var durationMin: Double = 0
    var isSMB = false
    var isExternal = false
    var isMutable = false

    /// The file's identity, `(type, timestamp.truncatedToSecond)`, with a temp basal pair as one dose.
    struct Identity: Hashable, Sendable {
        let kind: PumpEventKind
        let date: Date
    }

    /// What makes an update. Doubles in thousandths, so a JSON round-trip never "changes" a row.
    struct Signature: Equatable, Sendable {
        let units: Int64
        let rate: Int64
        let durationMin: Int64
        let isSMB: Bool
        let isExternal: Bool
        let isMutable: Bool
    }

    var identity: Identity { Identity(kind: kind, date: date) }

    var signature: Signature {
        Signature(
            units: Self.thousandths(units),
            rate: Self.thousandths(rate),
            durationMin: Self.thousandths(durationMin),
            isSMB: isSMB,
            isExternal: isExternal,
            isMutable: isMutable
        )
    }

    /// A temp basal's nominal length: pump rows carry `PumpHistoryStorage`'s +0.1 min ("to avoid tiny gaps"),
    /// Nightscout rows don't.
    var nominalDuration: TimeInterval {
        switch source {
        case .pump: .minutes(Swift.max(durationMin - 0.1, 0))
        case .nightscout: .minutes(Swift.max(durationMin, 0))
        }
    }

    /// A temp basal the pump reported delivered: final, with its delivered units.
    var deliveredUnits: Double? {
        guard kind == .tempBasal, !isMutable, units >= 0 else { return nil }
        return units
    }

    /// The time a change of this row touches: a temp basal its stored length.
    var span: DateInterval {
        switch kind {
        case .tempBasal:
            DateInterval(start: date, duration: Swift.max(.minutes(durationMin), 0))
        case .bolus,
             .resume,
             .suspend:
            DateInterval(start: date, duration: 0)
        }
    }

    private static func thousandths(_ value: Double) -> Int64 {
        guard value.isFinite else { return 0 }
        return Int64((value * 1000).rounded())
    }
}

extension PumpEventRecord {
    /// The rows of the pump history (`appCoordinator.pumpHistory`, any order), `source = pump`, in its order.
    /// - a temp basal pair (`.tempBasalDuration` id `X`, `.tempBasal` id `_X`) is one row, paired by id with the `_`
    ///   stripped (as the HealthKit and Nightscout mirrors do) and the same second; an unpaired half is skipped, and so
    ///   is a percent temp
    /// - two events of one kind in the same second are one row: the first one in the list
    /// - rewind, prime, alarms and the other types are not stored
    static func records(from history: [PumpHistoryEvent]) -> [PumpEventRecord] {
        let durations = Dictionary(
            history.filter { $0.type == .tempBasalDuration }.map { (PairKey($0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<Identity>()
        var records: [PumpEventRecord] = []
        for event in history {
            guard let record = record(event, durations: durations), seen.insert(record.identity).inserted else {
                continue
            }
            records.append(record)
        }
        return records
    }

    /// The identity of the row a pump history event maps to (either half of a temp basal pair gives the pair's);
    /// nil for the types that are not stored.
    static func identity(of event: PumpHistoryEvent) -> Identity? {
        guard let kind = kind(of: event.type) else { return nil }
        return Identity(kind: kind, date: event.timestamp.truncatedToSecond)
    }

    private static func kind(of type: EventType) -> PumpEventKind? {
        switch type {
        case .bolus: .bolus
        case .tempBasal,
             .tempBasalDuration: .tempBasal
        case .pumpSuspend: .suspend
        case .pumpResume: .resume
        default: nil
        }
    }

    /// A temp basal pair's halves: the id without the `_`, and the second.
    private struct PairKey: Hashable {
        let id: String
        let date: Date

        init(_ event: PumpHistoryEvent) {
            id = PumpEventRecord.strippedID(event.id)
            date = event.timestamp.truncatedToSecond
        }
    }

    private static func record(_ event: PumpHistoryEvent, durations: [PairKey: PumpHistoryEvent]) -> PumpEventRecord? {
        let date = event.timestamp.truncatedToSecond
        switch event.type {
        case .bolus:
            guard let amount = event.amount else { return nil }
            return PumpEventRecord(
                date: date,
                kind: .bolus,
                source: .pump,
                units: Double(amount),
                durationMin: event.duration.map { Double($0) } ?? 0,
                isSMB: event.isSMB == true,
                isExternal: event.isExternal == true,
                isMutable: event.isMutable == true
            )

        case .tempBasal:
            // driven by the rate half: the duration half alone is skipped
            guard event.temp != .percent,
                  let rate = event.rate,
                  let duration = durations[PairKey(event)],
                  let durationMin = duration.durationMin
            else { return nil }
            return PumpEventRecord(
                date: date,
                kind: .tempBasal,
                source: .pump,
                units: event.deliveredUnits.map { Double($0) } ?? -1,
                rate: Double(rate),
                durationMin: Double(durationMin),
                isMutable: event.isMutable == true || duration.isMutable == true
            )

        case .pumpSuspend:
            return PumpEventRecord(date: date, kind: .suspend, source: .pump)

        case .pumpResume:
            return PumpEventRecord(date: date, kind: .resume, source: .pump)

        default:
            return nil
        }
    }

    private static func strippedID(_ id: String) -> String {
        id.hasPrefix("_") ? String(id.dropFirst()) : id
    }
}

/// Where a `BasalScheduleRecord` row came from (its `source`).
enum BasalScheduleSource: Int16, Sendable, Hashable {
    /// recorded from `appCoordinator.basalProfile`
    case local = 0
    case nightscout = 1
}

/// A `BasalScheduleRecord` row as a value: the schedule in effect from `date` until the next record.
struct BasalScheduleRecordValue: Sendable, Equatable {
    let date: Date
    let source: BasalScheduleSource
    /// as `basal_profile.json` holds them: standard units
    let entries: [BasalProfileEntry]

    /// The normalized schedule (`minutes:rate`, the rate to 3 decimals, by start), to dedupe identical schedules.
    static func fingerprint(_ entries: [BasalProfileEntry]) -> String {
        entries
            .sorted { $0.minutes < $1.minutes }
            .map { "\($0.minutes):" + String(format: "%.3f", Double($0.rate)) }
            .joined(separator: ",")
    }

    /// The `entries` attribute: the `[BasalProfileEntry]` JSON of `basal_profile.json`.
    static func encode(_ entries: [BasalProfileEntry]) -> String? {
        guard let data = try? JSONCoding.encoder.encode(entries) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ entries: String) -> [BasalProfileEntry]? {
        try? JSONCoding.decoder.decode([BasalProfileEntry].self, from: Data(entries.utf8))
    }
}
