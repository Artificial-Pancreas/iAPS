import Foundation
import HealthKit

// MARK: - The device string

/// What a Nightscout entry's `device` says about the CGM (`NightscoutCGMDevice.parse`).
struct NightscoutCGMIdentity: Sendable, Equatable {
    /// `KnownPlugins.cgmIdForStatistics` (the source app for AppGroup); nil: only the family is known ("share2": a
    /// Dexcom), the backfill takes the recorded sessions' CGM of that family
    var cgmId: String?
    var family: CGMChoice.Family
    /// the sensor's or the transmitter's id, when the string carries one
    var sensorId: String?
}

/// The `device` of the readings iAPS uploads to Nightscout (`format`), and the CGM other uploaders' `device` names
/// (`parse`). Pure.
enum NightscoutCGMDevice {
    /// `HKDevice` fields that hold no name or id: LibreTransmitter's manufacturer without a transmitter type, the G7's
    /// sensor name before one pairs, LibreTransmitter's serial before a sensor reads
    static let placeholders: Set<String> = ["n/a", "unknown", "-"]

    /// Loop's format, "<manufacturer> <model> <id>": "Dexcom G6 8XXXXX", "Dexcom G7 DXCM12", "Abbott Libre 3
    /// 0D0000ABCD". The id is `sensorId` when the manager holds a sensor's serial, else the device's name when the
    /// device has a model (the G5/G6 transmitter's id); without a model the name is the product ("Senseonics Eversense
    /// E3", "Abbott MiaomiaoClient 3MH00ABCDE"). A part equal to the one before is left out (MockKit's name is its
    /// model). Firmware, software and battery are never in it: the string stays the same for a sensor. Without an
    /// `HKDevice`, or with nothing in it: `title` (the AppGroup source app, the manager's title).
    static func format(_ device: HKDevice?, sensorId: String?, title: String?) -> String? {
        guard let device else { return clean(title) }
        let model = clean(device.model)
        let name = clean(device.name)
        let id = clean(sensorId) ?? (model != nil ? name : nil)
        let product = model ?? (name != id ? name : nil)
        var parts: [String] = []
        for part in [clean(device.manufacturer), product, id].compactMap({ $0 }) where parts.last != part {
            parts.append(part)
        }
        return parts.isEmpty ? clean(title) : parts.joined(separator: " ")
    }

    /// A session's device holds its sensor's id: the id the string carries (`parse`), or `sensorId` inside it. Such a
    /// device is kept for the session (`CGMSessionRules.merged`, `live`): a later string of the same sensor that
    /// differs (a bridge's maker known later, a model) would split Nightscout's delta.
    static func hasID(_ device: String?, sensorId: String?) -> Bool {
        guard let device else { return false }
        if parse(device)?.sensorId != nil { return true }
        return sensorId.map { !$0.isEmpty && device.contains($0) } ?? false
    }

    /// A reading's uploaded device: its open session's (`session`, one that holds an id: `hasID`), unless the reading
    /// has a device of its own (`ownDevice`) naming another sensor than the session's (a batch can carry the previous
    /// sensor's readings after a new one paired); else the reading's (`computed`).
    static func live(_ computed: String?, ownDevice: Bool, session: String?) -> String? {
        guard let session else { return computed }
        guard ownDevice, let id = parse(computed)?.sensorId, id != parse(session)?.sensorId else { return session }
        return computed
    }

    /// Trimmed; nil when empty or a placeholder.
    static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !placeholders.contains(text.lowercased())
        else { return nil }
        return text
    }

    /// The Dexcom G7 family's sensor names (G7, ONE+, Stelo): what the G7 sensor ids start with
    static let dexcomSensorPrefixes = ["dxcm", "dx01", "dx02"]
    /// AAPS's and xDrip's names of the Libre 1/2 bridges and readers (`SourceSensor`, xDrip4iOS's BLE names): iAPS
    /// reads these through LibreTransmitter
    static let libreBridges = [
        "miaomiao", "bubble", "blucon", "tomato", "rfduino", "limitter", "glimp", "bluereader", "transmiterpl",
        "networklibre"
    ]

    /// The CGM a Nightscout entry's `device` names; nil for a string that names none (a follower, Trio's none,
    /// "loop://iPhone", a CGM iAPS has no plugin for). The uploaders' formats:
    /// - Loop and iAPS: "<manufacturer> <model> <id>" ("Dexcom G6 8XXXXX", "Dexcom G7 DXCM12", "Abbott Libre 3
    ///   <serial>", "Abbott MiaomiaoClient <serial>", "Senseonics Eversense E3", "Medtronic 722 Minimed500",
    ///   "LoopKit MockCGMManager"); iAPS's AppGroup source app ("xDrip4iOS", "Glucose Direct").
    /// - AAPS (`SourceSensor`): "G6 Native", "G5 Native", "G6 Native / G5 Native", "G7", "DexcomG5", "Dexcom G7 xDrip",
    ///   "Libre2", "Libre3", "Eversense", "MM600Series", the Libre 1 bridges ("Blucon", "Tomato", "LimiTTer", ...).
    /// - xDrip+: "xDrip-<collection method>[ <source info>]" ("xDrip-DexcomG5 G6 Native", "xDrip-LibreReceiver").
    /// - xDrip4iOS and Spike: the transmitter's BLE name ("DexcomAB", "DXCMxx", "MIAOMIAO1234", "Bubble ...").
    /// - share2nightscout-bridge: "share2"; nightscout-librelink-up: "nightscout-librelink-up" or "freestyle-libre".
    /// A Dexcom of no known model ("share2", "DexcomG5" which xDrip uses for the G6 too) and a Libre of no known
    /// generation (LibreLink Up) are the family only.
    static func parse(_ device: String?) -> NightscoutCGMIdentity? {
        guard let text = clean(device) else { return nil }
        let lower = text.lowercased()
        let words = text.split(separator: " ").map(String.init)
        let compact = Self.compact(lower)

        if lower.hasPrefix("xdrip-") {
            return xDrip(String(lower.dropFirst("xdrip-".count)))
        }
        if compact.hasPrefix("share2") || compact.hasPrefix("dexcomshare") || compact == "shfollow" {
            return dexcom(nil)
        }
        if compact.contains("librelink") || lower == "freestyle-libre" {
            return libre(nil)
        }
        switch compact {
        case "xdrip4ios": return NightscoutCGMIdentity(cgmId: "xdrip", family: .other)
        case "glucosedirect": return NightscoutCGMIdentity(cgmId: "glucoseDirect", family: .other)
        case "g6native": return dexcom("dexcomG6")
        case "g5native": return dexcom("dexcomG5")
        case "g6nativeg5native": return dexcom(nil)
        case "g7": return dexcom("dexcomG7")
        case "g6": return dexcom("dexcomG6")
        case "mm600series": return NightscoutCGMIdentity(cgmId: "enlite", family: .other)
        default: break
        }
        // "<manufacturer> <model> <id>": the id is the last word when it looks like one
        let id = words.count >= 3 ? words.last.flatMap { isID($0) ? $0 : nil } : nil
        let model = Self.compact(
            (id == nil ? words.dropFirst() : words.dropFirst().dropLast()).joined(separator: " ")
                .lowercased()
        )

        if words.first?.lowercased() == "dexcom", words.count > 1 {
            // AAPS's "Dexcom G5 xDrip" is xDrip's G5/G6 method; the ONE is a G6, the ONE+ and the Stelo G7s; no G4
            if model.hasPrefix("g5xdrip") { return dexcom(nil, id: id) }
            if model.hasPrefix("g5") { return dexcom("dexcomG5", id: id) }
            if model.hasPrefix("g6") { return dexcom("dexcomG6", id: id) }
            if ["g7", "one+", "stelo"].contains(where: { model.hasPrefix($0) }) { return dexcom("dexcomG7", id: id) }
            if model.hasPrefix("one") { return dexcom("dexcomG6", id: id) }
            if model.hasPrefix("g4") { return nil }
            return dexcom(nil, id: id)
        }
        if compact.hasPrefix("dexcom") {
            // AAPS's "DexcomG5" (xDrip's G5/G6 method), xDrip4iOS's BLE name "Dexcom" + the transmitter id's end
            let rest = compact.dropFirst("dexcom".count)
            switch rest {
            case "g6": return dexcom("dexcomG6")
            case "g7": return dexcom("dexcomG7")
            case "g5": return dexcom(nil)
            default: return dexcom(nil, id: rest.count == 2 ? text : nil)
            }
        }
        if dexcomSensorPrefixes.contains(where: { compact.hasPrefix($0) }), words.count == 1 {
            return dexcom("dexcomG7", id: text)
        }
        if compact.contains("libre3") {
            return libre("libre3", id: id)
        }
        if ["libretransmitter", "miaomiaoclient", "libre2", "libre1"].contains(where: { compact.contains($0) }) {
            return libre("libreTransmitter", id: id)
        }
        if let bridge = libreBridges.first(where: { compact.hasPrefix($0) }) {
            // a BLE name carries the bridge's id ("MIAOMIAO1234")
            return libre("libreTransmitter", id: compact.count > bridge.count && words.count == 1 ? text : nil)
        }
        if words.first?.lowercased() == "abbott" || compact.hasPrefix("freestyle") || compact.hasPrefix("abbott") {
            return libre(nil, id: id)
        }
        if compact.hasPrefix("senseonics") || compact.contains("eversense") {
            return NightscoutCGMIdentity(cgmId: "eversense", family: .other)
        }
        if compact.contains("minimed") {
            return NightscoutCGMIdentity(cgmId: "enlite", family: .other)
        }
        if compact.contains("mockcgmmanager") {
            return NightscoutCGMIdentity(cgmId: "simulator", family: .other)
        }
        return nil
    }

    /// xDrip+'s "<collection method>[ <source info>]", lowercased: the Dexcom and Libre methods; the follower,
    /// G4-wixel and other ones name no CGM iAPS knows.
    private static func xDrip(_ rest: String) -> NightscoutCGMIdentity? {
        let method = compact(String(rest.prefix { $0 != " " }))
        let info = compact(String(rest.drop { $0 != " " }))
        switch method {
        case "dexcomg5",
             "dexcomg6",
             "dexcomg7",
             "dexcomshare",
             "shfollow":
            if method == "dexcomg7" || info.contains("g7") { return dexcom("dexcomG7") }
            if method == "dexcomg6" || info.contains("g6") { return dexcom("dexcomG6") }
            if info.contains("g5") { return dexcom("dexcomG5") }
            return dexcom(nil)
        case "librealarm",
             "librereceiver":
            if info.contains("libre3") { return libre("libre3") }
            if info.contains("libre2") || info.contains("libre1") { return libre("libreTransmitter") }
            return libre(nil)
        case "limitter":
            return libre("libreTransmitter")
        default:
            return nil
        }
    }

    private static func dexcom(_ cgmId: String?, id: String? = nil) -> NightscoutCGMIdentity {
        NightscoutCGMIdentity(cgmId: cgmId, family: .dexcom, sensorId: id)
    }

    private static func libre(_ cgmId: String?, id: String? = nil) -> NightscoutCGMIdentity {
        NightscoutCGMIdentity(cgmId: cgmId, family: .libre, sensorId: id)
    }

    /// Letters, digits and "+" only.
    private static func compact(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber || $0 == "+" }
    }

    /// A sensor's or a transmitter's id: 4 or more letters and digits, with a digit or a G7 sensor name's prefix
    /// ("8XXXXX", "3MH00ABCDE", "DXCMab"), unlike a model's words ("Plus", "Mobile", "xDrip").
    private static func isID(_ word: String) -> Bool {
        guard word.count >= 4, word.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        let lower = word.lowercased()
        return word.contains(where: \.isNumber) || dexcomSensorPrefixes.contains { lower.hasPrefix($0) }
    }
}

// MARK: - The sessions

/// The backfilled CGM sessions from Nightscout entries' `device` and the Sensor Start / Sensor Change treatments.
/// Pure.
///
/// - Each entry's CGM is its `device`'s (`NightscoutCGMDevice.parse`); a family-only one ("share2") takes the recorded
///   CGM of that family nearest in time (none beyond `familyMatchWindow` when more than one model of it was
///   recorded), else it names none. Entries naming none are left out.
/// - Consecutive entries start a new sensor at a CGM change, a change of a known sensor id, or a Sensor Start or
///   Change between them; a gap of more than `gapSplit` starts a new session of the same sensor. A run of one id
///   longer than its CGM's life and `lifeGrace` (a G5/G6 transmitter's) is split at its largest gap.
/// - A new sensor's start is the Sensor Start or Change after the entry before it, up to `treatmentTolerance` after
///   its first entry; the first sensor's the latest one within its expected life before its first entry. Else unknown.
/// - A session reaches `edgeSlack` beyond its first and last entries, never into the next one; one started by a
///   Sensor Start begins at it.
/// - Recorded > entered > backfilled: the sessions are clipped to the time no recorded or entered session covers, and
///   to the window; a part holding no Unknown reading is dropped.
enum NightscoutCGMSessions {
    /// One Nightscout sgv entry with a `device`.
    struct Entry: Sendable, Equatable {
        let date: Date
        let device: String
    }

    /// Entries further apart than this are separate sessions (of the same sensor, unless something says otherwise):
    /// longer than any warm-up, so the CGM may have changed without an upload saying so.
    static let gapSplit: TimeInterval = .hours(6)
    /// A session reaches this before its first entry and after its last: a local reading's time can differ from the
    /// uploader's by up to a minute or so.
    static let edgeSlack: TimeInterval = .minutes(2)
    /// A Sensor Start up to this after a new sensor's first entry is its start: an uploader dating it at the warm-up's
    /// end, or by another clock (the readings' session tolerance).
    static let treatmentTolerance = BloodGlucose.sessionTolerance
    /// The first sensor's Sensor Start is looked for this far before its first entry when its CGM's life is unknown:
    /// a Libre's 14 days and a day.
    static let defaultLife: TimeInterval = .days(15)
    /// A sensor whose entries' median spacing is at most this is a 1-minute CGM.
    static let oneMinuteSpacing: TimeInterval = .minutes(2)
    /// A family-only device ("share2") is a recorded CGM of the family this near in time at most, when more than one
    /// model of the family was recorded: a month apart, the other model may as well have been in use.
    static let familyMatchWindow: TimeInterval = .days(30)
    /// A run of one id longer than its CGM's life and this is split at its largest gap: a G5/G6 transmitter's id
    /// outlives its sensors (the G7's 12 h grace, as a margin for any CGM).
    static let lifeGrace: TimeInterval = .hours(12)

    private struct Item {
        let date: Date
        let cgmId: String
        let sensorId: String?
        let device: String
    }

    private struct Group {
        var items: [Item]
        var start: Date
        var sensorStart: Date?
    }

    /// - Parameters:
    ///   - entries: the window's, any order
    ///   - sensorStarts: the Sensor Start and Change treatments' times, from up to `defaultLife` before the window
    ///   - stored: every stored session (effective: `CGMEnteredSessions.effective`), the backfilled ones ignored
    ///   - unknownTimes: the window's local readings no recorded or entered session covers, ascending
    static func sessions(
        entries: [Entry],
        sensorStarts: [Date],
        stored: [CGMSessionRecord],
        unknownTimes: [Date],
        window: DateInterval,
        newID: () -> UUID = { UUID() }
    ) -> [CGMSessionRecord] {
        let recorded = stored.filter { $0.source == .recorded }
        let covering = stored.filter { $0.source != .backfilled }
        let choices = CGMChoice.choices(recorded: recorded)
        let familyOf = Dictionary(choices.map { ($0.cgmId, $0.family) }, uniquingKeysWith: { first, _ in first })
        let recordedByFamily = Dictionary(grouping: CGMSessionRules.ordered(recorded)) { session in
            session.cgmId.flatMap { familyOf[$0] } ?? .other
        }
        /// a family-only device's CGM: the recorded one of the family nearest in time (the session holding the entry,
        /// else the last before it or the first after it, whichever is nearer); with more recorded models of the
        /// family than one, none beyond `familyMatchWindow`
        func resolve(_ identity: NightscoutCGMIdentity, at date: Date) -> String? {
            if let cgmId = identity.cgmId { return cgmId }
            guard identity.family != .other, let ofFamily = recordedByFamily[identity.family] else { return nil }
            func distance(_ session: CGMSessionRecord) -> TimeInterval {
                if session.contains(date) { return 0 }
                return session.start > date ? session.start.timeIntervalSince(date) :
                    date.timeIntervalSince(session.end ?? .distantFuture)
            }
            let around = [ofFamily.last { $0.start <= date }, ofFamily.first { $0.start > date }].compactMap { $0 }
            guard let nearest = around.min(by: { distance($0) < distance($1) }) else { return nil }
            let models = Set(ofFamily.compactMap(\.cgmId))
            guard models.count == 1 || distance(nearest) <= familyMatchWindow else { return nil }
            return nearest.cgmId
        }
        let inside = entries.filter { window.contains($0.date) }.sorted { $0.date < $1.date }
        let items: [Item] = inside.compactMap { entry in
            guard let identity = NightscoutCGMDevice.parse(entry.device),
                  let cgmId = resolve(identity, at: entry.date)
            else {
                return nil
            }
            return Item(date: entry.date, cgmId: cgmId, sensorId: identity.sensorId, device: entry.device)
        }
        let starts = Array(Set(sensorStarts)).sorted()
        func life(_ cgmId: String) -> TimeInterval {
            choices.first { $0.cgmId == cgmId }?.expectedLife ?? defaultLife
        }

        var groups: [Group] = []
        var used = Set<Date>()
        /// the latest unused Sensor Start in the range
        func sensorStart(after: Date, upTo: Date) -> Date? {
            let start = starts.last { $0 > after && $0 <= upTo && !used.contains($0) }
            if let start { used.insert(start) }
            return start
        }
        for item in items {
            guard var current = groups.last, let last = current.items.last else {
                let start = sensorStart(
                    after: item.date.addingTimeInterval(-life(item.cgmId)),
                    upTo: item.date.addingTimeInterval(treatmentTolerance)
                )
                groups.append(Group(items: [item], start: item.date, sensorStart: start))
                continue
            }
            let treated = starts.contains { $0 > last.date && $0 <= item.date && !used.contains($0) }
            let otherSensor = item.sensorId != nil && last.sensorId != nil && item.sensorId != last.sensorId
            if treated || otherSensor || item.cgmId != last.cgmId {
                let start = sensorStart(after: last.date, upTo: item.date.addingTimeInterval(treatmentTolerance))
                groups.append(Group(items: [item], start: Swift.min(start ?? item.date, item.date), sensorStart: start))
            } else if item.date.timeIntervalSince(last.date) > gapSplit {
                // the same sensor after a gap
                groups.append(Group(items: [item], start: item.date, sensorStart: current.sensorStart))
            } else {
                current.items.append(item)
                groups[groups.count - 1] = current
            }
        }

        // a run of one id longer than a sensor lasts (a G5/G6 transmitter's): split at its largest gap, the later
        // part a sensor of unknown start
        func split(_ group: Group) -> [Group] {
            guard let first = group.items.first, let last = group.items.last, first.sensorId != nil,
                  last.date.timeIntervalSince(first.date) > life(first.cgmId) + lifeGrace
            else { return [group] }
            let cut = group.items.indices.dropLast().max { a, b in
                group.items[a + 1].date.timeIntervalSince(group.items[a].date) <
                    group.items[b + 1].date.timeIntervalSince(group.items[b].date)
            } ?? 0
            let later = Array(group.items[(cut + 1)...])
            return split(Group(items: Array(group.items[...cut]), start: group.start, sensorStart: group.sensorStart)) +
                split(Group(items: later, start: later[0].date, sensorStart: nil))
        }
        groups = groups.flatMap(split)

        var sessions: [CGMSessionRecord] = []
        for (index, group) in groups.enumerated() {
            guard let first = group.items.first, let last = group.items.last else { continue }
            // from the slack before the first entry (or the Sensor Start that began it) to the slack after the last,
            // never into the next session, always holding its own entries
            func reach(_ group: Group, _ first: Item) -> Date {
                Swift.min(group.start, first.date.addingTimeInterval(-edgeSlack))
            }
            let start = Swift.max(reach(group, first), sessions.last?.end ?? .distantPast)
            var end = last.date.addingTimeInterval(edgeSlack)
            if index + 1 < groups.count, let next = groups[index + 1].items.first {
                end = Swift.max(Swift.min(end, reach(groups[index + 1], next)), last.date.addingTimeInterval(1))
            }
            let choice = choices.first { $0.cgmId == first.cgmId }
            let spacings = zip(group.items, group.items.dropFirst()).map { $1.date.timeIntervalSince($0.date) }.sorted()
            let median = spacings.isEmpty ? nil : spacings[spacings.count / 2]
            let devices = Dictionary(grouping: group.items, by: \.device)
            sessions.append(CGMSessionRecord(
                id: newID(),
                start: start,
                end: Swift.max(end, start),
                CGMSnapshot(
                    plugin: choice?.plugin ?? first.cgmId,
                    cgmId: first.cgmId,
                    name: choice?.name ?? first.device,
                    sensorStart: group.sensorStart,
                    expectedLife: choice?.expectedLife,
                    oneMinute: median.map { $0 <= oneMinuteSpacing } ?? false,
                    sensorId: group.items.lazy.compactMap(\.sensorId).first,
                    device: devices.max { ($0.value.count, $1.key) < ($1.value.count, $0.key) }?.key
                ),
                source: .backfilled
            ))
        }

        // recorded > entered > backfilled, inside the window, each part with an Unknown reading
        let pieces = CGMEnteredSessions.clipped(sessions, outside: covering.map(\.interval)).compactMap { piece in
            piece.interval.intersection(with: window).map { part -> CGMSessionRecord in
                var piece = piece
                piece.start = part.start
                piece.end = part.end
                return piece
            }
        }
        return pieces.filter { piece in
            let index = unknownTimes.partitionIndex { $0 >= piece.start }
            return index < unknownTimes.count && piece.contains(unknownTimes[index])
        }
    }
}

// MARK: - The backfill

/// The Sensor Start and Sensor Change treatments (`NightscoutAPI.fetchCGMTreatments`), each paged on its own.
enum NightscoutCGMQuery: String, Sendable, CaseIterable {
    case sensorStarts = "Sensor Start"
    case sensorChanges = "Sensor Change"

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "find[eventType]", value: rawValue)]
    }
}

/// The GETs of the CGM backfill (`NightscoutAPI` in the app; the tests fake the server).
struct NightscoutCGMBackfillSource: Sendable {
    /// one page of a query's treatments in the interval (both ends included), newest first
    let treatments: @Sendable(NightscoutCGMQuery, DateInterval) async throws -> [NightscoutInsulinTreatment]
}

/// What a CGM backfill did.
struct NightscoutCGMBackfillOutcome: Sendable, Equatable {
    /// the window's readings no recorded or entered session covers
    var unknown = 0
    /// of them, the ones a backfilled session names now
    var named = 0
    /// the backfilled sessions written
    var sessions = 0
    /// why it stopped (a treatment page, the write); nil: it ran
    var failure: String?
}

/// The read-only Nightscout backfill of which CGM gave the Unknown readings: it runs with the glucose backfill, over
/// the days it fetched (the same Days setting, at most the CGM topic's 90 days), from the entries it fetched (their
/// `device`) and the Sensor Start / Sensor Change treatments (paged GETs). It writes only `CGMSession` rows
/// (`CGMSessionStore.storeBackfilled`), never anything to Nightscout.
enum NightscoutCGMBackfill {
    /// Readings older than this aren't named: the CGM topic's longest period.
    static let maxAge: TimeInterval = .days(90)
    /// The treatments are fetched from this before the window: the first sensor's Sensor Start.
    static let treatmentLookback = NightscoutCGMSessions.defaultLife

    /// The window: the glucose backfill's complete time (from `from`, its start or the newest point a failed page
    /// stopped at), at most `maxAge`, to now; nil when empty.
    static func window(from: Date, now: Date) -> DateInterval? {
        let start = Swift.max(from, now.addingTimeInterval(-maxAge))
        return start < now ? DateInterval(start: start, end: now) : nil
    }

    /// The window's Unknown readings (no recorded or entered session covers them), the treatments when there are
    /// some, the sessions built (`NightscoutCGMSessions.sessions`) and written over the window
    /// (`CGMSessionStore.storeBackfilled`: the backfilled time of the window is replaced).
    /// - Parameters:
    ///   - entries: the glucose backfill's sgv entries with a `device`
    ///   - readings: the window's local reading times, any order
    ///   - sessions: every stored session (`CGMSessionStore.sessions`)
    ///   - store: writes the sessions, replacing the backfilled ones in the interval; returns whether it succeeded
    static func run(
        entries: [NightscoutCGMSessions.Entry],
        window: DateInterval,
        readings: [Date],
        sessions: [CGMSessionRecord],
        source: NightscoutCGMBackfillSource,
        store: @Sendable([CGMSessionRecord], DateInterval) async -> Bool
    ) async -> NightscoutCGMBackfillOutcome {
        var outcome = NightscoutCGMBackfillOutcome()
        let covering = sessions.filter { $0.source != .backfilled }
        let inside = readings.filter { window.contains($0) }.sorted()
        let unknown = CGMSessionAttribution.attribute(inside, to: covering) { $0 }.unknown
        outcome.unknown = unknown.count
        guard unknown.isNotEmpty else { return outcome }

        var starts: [Date] = []
        let since = window.start.addingTimeInterval(-treatmentLookback)
        for query in NightscoutCGMQuery.allCases {
            let pages = await BaseNightscoutManager.fetchTreatmentPages(
                since: since,
                until: window.end,
                date: { $0.createdAt },
                key: { $0.pagingKey },
                page: { try await source.treatments(query, $0) },
                reached: { _ in }
            )
            if let error = pages.error {
                outcome.failure = error.localizedDescription
                return outcome
            }
            starts += pages.entries.filter { $0.isValid != false && $0.eventType == query.rawValue }
                .compactMap(\.createdAt)
        }

        let built = NightscoutCGMSessions.sessions(
            entries: entries,
            sensorStarts: starts,
            stored: sessions,
            unknownTimes: unknown,
            window: window
        )
        guard await store(built, window) else {
            outcome.failure = NSLocalizedString(
                "the sessions could not be saved",
                comment: "Glucose backfill result: why naming the CGMs failed"
            )
            return outcome
        }
        outcome.sessions = built.count
        outcome.named = CGMSessionAttribution.attribute(unknown, to: built) { $0 }.bySession
            .reduce(0) { $0 + $1.readings.count }
        debug(
            .nightscout,
            "CGM backfill: \(entries.count) entries with a device, \(starts.count) sensor starts, " +
                "\(built.count) sessions naming \(outcome.named) of \(outcome.unknown) Unknown readings"
        )
        return outcome
    }
}

extension CGMSessionAttribution {
    /// The Nightscout `device` of the session holding `date` (the latest starting one, as `attribute` takes it); nil
    /// when none holds it or it has none. The re-upload of the stored readings (`NightscoutConfig.StateModel`).
    static func device(at date: Date, _ sessions: [CGMSessionRecord]) -> String? {
        sessions.filter { $0.contains(date) }.max { $0.start < $1.start }?.device
    }
}
