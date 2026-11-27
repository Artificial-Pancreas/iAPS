import Foundation

/// Why a pod or patch ended.
enum PatchEndReason: String, Sendable, Equatable, CaseIterable {
    case expired
    case ranEmpty
    case occlusionOrFault
    case removedEarly
}

/// What a session is of: a pod (Omnipod), a patch (Medtrum, any other pod or patch plugin) or a tube pump's infusion
/// set (a site).
enum PatchKind: Sendable, Hashable {
    case patch
    case pod
    case site

    /// The kind of a plugin's sessions: a tube pump's (and none's: a Nightscout session imported without a pump, which
    /// the rules treat as a site) are sites.
    init(plugin: String?) {
        if plugin == PatchStatsEngine.omnipodPlugin {
            self = .pod
        } else if PumpSessionRules.isPodOrPatch(plugin) {
            self = .patch
        } else {
            self = .site
        }
    }
}

/// A pod, a patch or a tube pump's site, as the topic shows it: a pump session (`PumpSessionValue`, either source)
/// mapped by `PatchStatsEngine.sessions`.
struct PatchSession: Sendable, Equatable, Identifiable {
    /// the `PumpSession` row's id (a tube site merged with the Nightscout one before it: the pump session's)
    let id: String
    /// the pump plugin's identifier ("Medtrum", "Omni", "Dana"); nil: unknown (imported from Nightscout without a pump)
    let plugin: String?
    let kind: PatchKind
    /// what its wear and its hours of age count from: its activation (the change), or its start when none is known
    /// (`isActivationKnown`)
    let activation: Date
    /// false: no activation is known (a Nightscout piece before the first Site Change, a tube site seeded or started
    /// without its change event): partial, its wear is the time recorded
    let isActivationKnown: Bool
    /// its end (an open one's: the last heartbeat)
    let end: Date
    /// where its numbers start: the activation, or its start when that is more than the slack after it, or no activation
    /// is known (`isPartial`)
    let dataStart: Date
    /// the uncovered stretches inside `[dataStart, end]` of `PatchStatsEngine.minimumGap` or longer, oldest -> newest
    let gaps: [DateInterval]
    /// a pump session going on (no end yet): the one in use while its pump delivers (`PatchStatsEngine.inUse`)
    var isOpen = false
    /// the covered time in `[dataStart, end]`, s (0: no pump data yet: nothing to compare)
    var coveredSeconds: TimeInterval = 0
    /// The site it was worn on: stored on the row, not shown yet (a later PR adds its entry and display).
    var site: String?
    /// The insulin it was filled with, U: not shown yet (a later PR).
    var filledUnits: Double?
    /// Why it ended: stored on the row (the pump's, Nightscout's alarm), not shown yet (a later PR).
    var endReason: PatchEndReason?

    /// from the activation to the end
    var wear: TimeInterval { end.timeIntervalSince(activation) }
    /// activated before its data begins (or when, unknown): its numbers count from `dataStart`
    var isPartial: Bool { !isActivationKnown || dataStart > activation }
    /// `[activation, end]`
    var span: DateInterval { DateInterval(start: activation, end: Swift.max(activation, end)) }
    /// `[dataStart, end]`: the time its numbers are over
    var dataSpan: DateInterval { DateInterval(start: dataStart, end: Swift.max(dataStart, end)) }
    /// the gaps' time, s
    var gapSeconds: TimeInterval { gaps.reduce(0) { $0 + $1.duration } }
    /// Its wear counts (the wear tile, the wear days): its activation is known, and it isn't a site worn longer than
    /// `PatchStatsEngine.scaleWearLimit` (any site: a tube pump's seeded or lost-event one runs on). It is listed
    /// either way.
    var isWearCounted: Bool {
        isActivationKnown && !(kind == .site && wear > PatchStatsEngine.scaleWearLimit)
    }

    /// Today compares it with the ones before it: its age is known and it has pump data
    var isComparable: Bool { isActivationKnown && coveredSeconds > 0 }
}

/// The topic's naming: the kind of the current pump's sessions, or (without a pump) of the newest session.
struct PatchTopic: Sendable, Equatable {
    let kind: PatchKind

    init(kind: PatchKind) {
        self.kind = kind
    }

    init(plugin: String?) {
        kind = PatchKind(plugin: plugin)
    }

    /// Omnipod: "Pods"
    var isPods: Bool { kind == .pod }
}

/// What a session, a wear day or a part of either holds, summed over its time. Additive: wear days and sessions pool
/// by `+`, and every share and rate is taken of the sum.
struct PatchNumbers: Sendable, Equatable, BandSharesProviding {
    /// the time counted, s
    var seconds: Double = 0
    /// U, every delivery segment (temps outside coverage too)
    var basal: Double = 0
    var smb: Double = 0
    /// U, the pump's other boluses
    var bolus: Double = 0
    /// U, External Insulin (a pen): not from the pod or patch
    var external: Double = 0
    /// the pump coverage in it, s
    var coveredSeconds: Double = 0
    /// the time the IOB rows stand for, and the part of it below zero, s
    var iobSeconds: Double = 0
    var negativeIOBSeconds: Double = 0
    /// the time the CGM readings stand for, s, and its part in each band (by `GlucoseBand.rawValue`)
    var glucoseSeconds: Double = 0
    var bandSeconds: [Double] = Array(repeating: 0, count: GlucoseBand.allCases.count)
    /// Σ mg/dL × s and Σ (mg/dL)² × s of the readings: the mean and the CV
    var glucoseSum: Double = 0
    var glucoseSquares: Double = 0
    /// the loops' slots and their successes (`HomeLoopStats.Slots`); the sessions' whole only
    var loopSlots = 0
    var loopSuccesses = 0

    static let zero = PatchNumbers()

    static func + (lhs: PatchNumbers, rhs: PatchNumbers) -> PatchNumbers {
        var sum = lhs
        sum.seconds += rhs.seconds
        sum.basal += rhs.basal
        sum.smb += rhs.smb
        sum.bolus += rhs.bolus
        sum.external += rhs.external
        sum.coveredSeconds += rhs.coveredSeconds
        sum.iobSeconds += rhs.iobSeconds
        sum.negativeIOBSeconds += rhs.negativeIOBSeconds
        sum.glucoseSeconds += rhs.glucoseSeconds
        sum.bandSeconds = zip(lhs.bandSeconds, rhs.bandSeconds).map { $0 + $1 }
        sum.glucoseSum += rhs.glucoseSum
        sum.glucoseSquares += rhs.glucoseSquares
        sum.loopSlots += rhs.loopSlots
        sum.loopSuccesses += rhs.loopSuccesses
        return sum
    }

    static func pooled(_ numbers: [PatchNumbers]) -> PatchNumbers {
        numbers.reduce(.zero, +)
    }

    /// A share of it (`share` of its time): every amount and time by the share, the loops left out. Prorates the hour
    /// an age falls in (`PatchStats.numbers(from:to:)`).
    func scaled(by share: Double) -> PatchNumbers {
        var part = PatchNumbers()
        part.seconds = seconds * share
        part.basal = basal * share
        part.smb = smb * share
        part.bolus = bolus * share
        part.external = external * share
        part.coveredSeconds = coveredSeconds * share
        part.iobSeconds = iobSeconds * share
        part.negativeIOBSeconds = negativeIOBSeconds * share
        part.glucoseSeconds = glucoseSeconds * share
        part.bandSeconds = bandSeconds.map { $0 * share }
        part.glucoseSum = glucoseSum * share
        part.glucoseSquares = glucoseSquares * share
        return part
    }

    /// U from the reservoir: basal, SMBs and the pump's boluses (External Insulin left out)
    var total: Double { basal + smb + bolus }

    /// The basal scaled to the whole time by its covered time (the Insulin tab's rule, `DayInsulin.scaledBasal`); the
    /// boluses are not.
    var scaledBasal: Double { coveredSeconds > 0 ? basal * seconds / coveredSeconds : basal }

    /// U per 24 h: basal (scaled), SMB, bolus with External Insulin (the Insulin tab's parts); nil without covered time
    /// (the basal is unknown)
    var partsPerDay: [Double]? {
        guard seconds > 0, coveredSeconds > 0 else { return nil }
        let factor = TimeInterval.days(1) / seconds
        return [scaledBasal * factor, smb * factor, (bolus + external) * factor]
    }

    /// U per 24 h, External Insulin included (the Insulin tab's TDD rule); nil without covered time
    var perDay: Double? { partsPerDay.map { $0.reduce(0, +) } }

    var hasGlucose: Bool { glucoseSeconds > 0 }

    /// of the CGM time (all 0 without readings)
    var bandShares: BandShares { BandShares(seconds: bandSeconds, total: glucoseSeconds) }

    /// the in-range band's percent (largest remainder, as everywhere); nil without readings
    var inRangePercent: Int? { hasGlucose ? percent(.inRange) : nil }

    /// mg/dL, time-weighted; nil without readings
    var mean: Double? { hasGlucose ? glucoseSum / glucoseSeconds : nil }

    /// %, the time-weighted population SD over the mean; nil without readings
    var cv: Double? {
        guard let mean, mean > 0 else { return nil }
        let variance = Swift.max(0, glucoseSquares / glucoseSeconds - mean * mean)
        return variance.squareRoot() / mean * 100
    }

    /// the CGM time of the time counted, 0...1; nil without time
    var cgmShare: Double? { seconds > 0 ? Swift.min(glucoseSeconds / seconds, 1) : nil }

    /// successes ÷ slots, %; nil without slots
    var loopPercent: Double? { loopSlots > 0 ? Double(loopSuccesses) / Double(loopSlots) * 100 : nil }

    /// s per 24 h of IOB time (the Insulin tab's rule); nil without IOB rows
    var negativeIOBPerDay: Double? { iobSeconds > 0 ? negativeIOBSeconds / iobSeconds * .days(1) : nil }
}

/// A session's numbers: over its time, by wear day, and by hour of age (any age's numbers are summed from them: Today's
/// comparison).
struct PatchStats: Sendable, Equatable, Identifiable {
    let session: PatchSession
    /// the patch in use (`PatchStatsEngine.inUse`)
    let isInUse: Bool
    /// over `dataSpan`, with the loops
    let whole: PatchNumbers
    /// Hour k of age is `[activation + k h, activation + (k + 1) h)` inside the data span, the last one up to the end;
    /// an hour before the recording's start has no time (`seconds` 0).
    let hours: [PatchNumbers]
    /// Day 1 first, up to the last day it reached (`hours` by 24); a day before the recording's start has no time
    let wearDays: [PatchNumbers]

    var id: String { session.id }

    init(session: PatchSession, isInUse: Bool, whole: PatchNumbers, hours: [PatchNumbers]) {
        self.session = session
        self.isInUse = isInUse
        self.whole = whole
        self.hours = hours
        let count = PatchStatsEngine.dayIndex(at: session.wear) + 1
        wearDays = (0 ..< count).map { day in
            PatchNumbers.pooled(Array(hours[Swift.min(day * 24, hours.count) ..< Swift.min((day + 1) * 24, hours.count)]))
        }
    }

    /// Its numbers between two ages, s after the activation: the hours inside in full, the hour `to` falls in
    /// prorated by its share of that hour's time (the hours keep no times within them).
    func numbers(from: TimeInterval = 0, to: TimeInterval) -> PatchNumbers {
        let hour = TimeInterval.hours(1)
        let first = Swift.max(0, Int((from / hour).rounded(.down)))
        var sum = PatchNumbers.zero
        var index = first
        while index < hours.count, Double(index) * hour < to {
            let bucket = hours[index]
            let bucketEnd = Swift.min(Double(index + 1) * hour, session.wear)
            if to >= bucketEnd {
                sum = sum + bucket
            } else if bucket.seconds > 0 {
                // the bucket's time ends at its hour's end (or the session's); it starts that long before
                let start = bucketEnd - bucket.seconds
                sum = sum + bucket.scaled(by: Swift.min(Swift.max((to - start) / bucket.seconds, 0), 1))
            }
            index += 1
        }
        return sum
    }

    /// By wear day up to an age (the last one cut there), Day 1 first.
    func wearDays(upTo age: TimeInterval) -> [PatchNumbers] {
        let end = Swift.min(age, session.wear)
        return (0 ... PatchStatsEngine.dayIndex(at: end)).map { day in
            numbers(from: Double(day) * PatchStatsEngine.wearDay, to: Swift.min(Double(day + 1) * PatchStatsEngine.wearDay, end))
        }
    }
}

/// A wear day over the sessions: their time in it, pooled (`PatchStatsEngine.byWearDay`).
struct PatchWearDay: Sendable, Equatable, Identifiable {
    /// 0: Day 1
    let index: Int
    /// the sessions with time in it
    let sessions: Int
    let numbers: PatchNumbers

    var id: Int { index }
}

/// What the numbers of the sessions are computed from: the read range's rows (the Insulin tab's and the glucose
/// statistics' reads, and the loop records).
struct PatchInput: Sendable, Equatable {
    /// the events (with the state running into the range), the coverage, the schedules and the IOB rows
    var insulin = InsulinInput()
    /// the CGM readings, from `GlucoseStatistics.Config.lookback` before the range
    var glucose: [GlucosePoint] = []
    /// the loop records started in the range
    var loops: [HomeLoopStats.Record] = []
}

/// The pod, patch and site statistics, as pure functions: no Core Data, no `Date()`, no global calendar.
///
/// **Sessions** are the pump sessions as stored (`PumpSessionValue`, both sources: `PumpSessionRules` writes them),
/// mapped one to one for display (`sessions`), with these rules of the reader only:
/// - a zero-length one (nothing covered yet) is left out, but the open pump session (its next heartbeat extends it);
/// - a partial pod or patch (its activation unknown, or more than the slack before its start) longer than its
///   plugin's `maximumLife` is left out: more than one unit's life is more than one unit, so no row of it (or of a part
///   of it) would be one pod or patch. Its time still counts on the Insulin topic (the coverage);
/// - a pod's or patch's expiry tail is left out: a Nightscout piece without an activation, at most `expiryTailLimit`
///   long, starting within the slack of an earlier session's `activation + maximumLife` of its plugin (a unit worn to
///   its end without an alarm: the evidence joined up to the next Site Change). A longer one is another unit whose Site
///   Change is missing: shown, its activation unknown. Its time counts on the Insulin topic either way;
/// - a Nightscout session kept for the user's fields that overlaps another session is not shown (nor are its fields);
///   the left-out ones above don't count as others;
/// - a tube pump's site seeded or started without its change event (no activation) joins the Nightscout site that
///   ends within `PumpSessionRules.Config.siteChangeCluster` of its start (the same set change, counted once).
///
/// **In use:** the open pump session of the plugin delivering now (`KnownPlugins.hasActiveDeliveryUnit`).
///
/// **Numbers.** Insulin from the Insulin tab's delivery timeline, boluses and IOB spans (`InsulinStatsEngine`), the
/// glucose from the glucose engine's weighted readings (`GlucoseStatsEngine`), the loops per slot (`HomeLoopStats`),
/// each by hour of age. Wear day N is the 24 hours from N − 1 days after the activation; the days go as far as the
/// longest session.
enum PatchStatsEngine {
    /// A stretch without coverage this long or longer is a gap (`PumpSessionRules.Config.slack`: a heartbeat that late
    /// records one), so only the wait for the first heartbeat after an activation is shorter.
    static let minimumGap: TimeInterval = PumpSessionRules.Config.slack
    /// An expiry tail (`sessions`) is at most this long: the Nightscout evidence joins temps this far apart
    /// (`PumpEventStore.Config.nightscoutCoverageGap`), so a unit worn to its end runs on in the evidence up to the next
    /// Site Change by no more than this
    static let expiryTailLimit: TimeInterval = PumpEventStore.Config.nightscoutCoverageGap
    /// Today compares the patch in use with the patches before it, up to this many
    static let previousCount = 10
    static let wearDay: TimeInterval = .days(1)
    /// a wear day gets a row from this much pooled time in it (a session of 72 h and a second adds no Day 4)
    static let minimumWearDayTime: TimeInterval = .hours(1)
    /// the time after the wear limit the pod or patch still delivers
    static let grace: TimeInterval = .hours(8)
    /// sessions worn longer than this don't set the wear bars' scale: a clock set back can make one of months
    static let scaleWearLimit: TimeInterval = .days(14)

    static let medtrumPlugin = "Medtrum"
    static let omnipodPlugin = "Omni"

    /// Medtrum and Omnipod are worn 3 days (then the grace): the tick on the wear bar; nil for the others (a site).
    static func wearLimit(plugin: String?) -> TimeInterval? {
        switch plugin {
        case medtrumPlugin,
             omnipodPlugin: return .days(3)
        default: return nil
        }
    }

    /// The longest a pod or patch can deliver, the grace included: Medtrum's extended mode, 112 h + 8 h (MedtrumKit
    /// `ExpiryMode`: 72 h or 112 h); Omnipod's 72 h + 8 h. nil for the others (a site). Not the wear bar's tick
    /// (`wearLimit`).
    static func maximumLife(plugin: String?) -> TimeInterval? {
        switch plugin {
        case medtrumPlugin: return .hours(112 + 8)
        case omnipodPlugin: return .hours(72 + 8)
        default: return nil
        }
    }

    // MARK: - Sessions

    /// A session on its way to display: the row's, or a tube site and the Nightscout site before it, joined.
    private struct Shown {
        let id: UUID
        let plugin: String?
        let kind: PatchKind
        var activation: Date?
        var start: Date
        let end: Date
        /// sorted, merged
        var covered: [DateInterval]
        let isOpen: Bool
    }

    /// The pump sessions shown (the type's rules), newest -> oldest by activation.
    /// - Parameter records: `CoreDataStorage.fetchPumpSessions`'s, both sources, any order
    static func sessions(_ records: [PumpSessionValue]) -> [PatchSession] {
        let rows = shownRows(records)
        return joiningTubeSites(hidingAnnotationOverlaps(rows), rows: rows)
            .map(patchSession)
            .sorted { ($0.activation, $0.id) > ($1.activation, $1.id) }
    }

    /// The row is the pump's session still running.
    private static func isOpenPumpRow(_ row: PumpSessionValue) -> Bool { row.source == .pump && row.end == nil }
    /// The row's last known moment: its end or its last heartbeat, the later one.
    private static func seenUntil(_ row: PumpSessionValue) -> Date { Swift.max(row.lastSeen, row.end ?? row.lastSeen) }
    private static func rowsOverlap(_ a: PumpSessionValue, _ b: PumpSessionValue) -> Bool {
        a.start < seenUntil(b) && b.start < seenUntil(a)
    }

    /// The rows that can be sessions, oldest -> newest by start: none zero-length, none more than one pod or patch, none
    /// the expiry tail of an earlier unit.
    private static func shownRows(_ records: [PumpSessionValue]) -> [PumpSessionValue] {
        let slack = PumpSessionRules.Config.slack
        // zero-length: nothing covered (an event without a heartbeat after it, a unit that never delivered, a split
        // at a start); the open pump session stays, the next heartbeat extends it
        let rows = records.filter { $0.lastSeen > $0.start || isOpenPumpRow($0) }
            .sorted { ($0.start, $0.id.uuidString) < ($1.start, $1.id.uuidString) }
        func isPodOrPatch(_ row: PumpSessionValue) -> Bool {
            !row.flags.contains(.site) && PatchKind(plugin: row.plugin) != .site
        }
        return rows.filter { row in
            guard isPodOrPatch(row), !isOpenPumpRow(row) else { return true }
            let isPartial = row.activation.map { row.start.timeIntervalSince($0) > slack } ?? true
            // more than a pod's or patch's life without its activation: more than one unit
            if isPartial, let life = maximumLife(plugin: row.plugin), seenUntil(row).timeIntervalSince(row.start) > life {
                return false
            }
            // the expiry tail of an earlier unit of its plugin (any session between them: an annotated row, another pump)
            if row.source == .nightscout, row.activation == nil,
               seenUntil(row).timeIntervalSince(row.start) <= expiryTailLimit,
               rows.contains(where: { other in
                   guard let activation = other.activation, other.start < row.start,
                         row.plugin == nil || other.plugin == row.plugin,
                         let life = maximumLife(plugin: other.plugin)
                   else { return false }
                   return abs(row.start.timeIntervalSince(activation.addingTimeInterval(life))) <= slack
               })
            {
                return false
            }
            return true
        }
    }

    /// The rows on their way to display, without a Nightscout session kept for the user's fields over another session
    /// (its Site Change moved by more than the cluster, or deleted; one over the local time): the other one is the
    /// session. Of two such, the older one (both with the same start: both).
    private static func hidingAnnotationOverlaps(_ rows: [PumpSessionValue]) -> [Shown] {
        // TODO: the entered details PR shows its fields on the session it overlaps (or merges them into it).
        var hidden = Set<UUID>()
        for row in rows where row.source == .nightscout && row.hasUserFields {
            if rows.contains(where: { other in
                other.id != row.id && !hidden.contains(other.id) && rowsOverlap(row, other)
                    && (other.source == .pump || !other.hasUserFields || other.start < row.start)
            }) {
                hidden.insert(row.id)
            }
        }

        return rows.filter { !hidden.contains($0.id) }.map { row in
            Shown(
                id: row.id,
                plugin: row.plugin,
                kind: row.flags.contains(.site) ? .site : PatchKind(plugin: row.plugin),
                activation: row.activation,
                start: row.start,
                end: Swift.max(seenUntil(row), row.start),
                covered: StatsIntervals.mergedKeepingEmpty(row.covered),
                isOpen: isOpenPumpRow(row)
            )
        }
    }

    /// A tube site without its change (seeded, or started without the event) joined with the Nightscout site of the
    /// same plugin (or none) ending within the cluster of its start: the same set change; it starts there, with its
    /// activation.
    /// - Parameter rows: the rows the sessions are of (their sources)
    private static func joiningTubeSites(_ shown: [Shown], rows: [PumpSessionValue]) -> [Shown] {
        var shown = shown
        let sources = Dictionary(rows.map { ($0.id, $0.source) }, uniquingKeysWith: { first, _ in first })
        var joined = Set<UUID>()
        for index in shown.indices where sources[shown[index].id] == .pump && shown[index].kind == .site
            && shown[index].activation == nil
        {
            let site = shown[index]
            guard let before = shown.indices.filter({ other in
                let candidate = shown[other]
                return sources[candidate.id] == .nightscout && !joined.contains(candidate.id) && candidate.kind == .site
                    && (candidate.plugin == site.plugin || candidate.plugin == nil) && candidate.start < site.start
                    && abs(candidate.end.timeIntervalSince(site.start)) <= PumpSessionRules.Config.siteChangeCluster
            }).max(by: { shown[$0].end < shown[$1].end }) else { continue }
            joined.insert(shown[before].id)
            shown[index].start = shown[before].start
            shown[index].activation = shown[before].activation
            shown[index].covered = StatsIntervals.mergedKeepingEmpty(shown[before].covered + site.covered)
        }
        shown.removeAll { joined.contains($0.id) }
        return shown
    }

    /// The session shown: its activation (a partial one's start without it), its data span and gaps.
    private static func patchSession(_ session: Shown) -> PatchSession {
        let slack = PumpSessionRules.Config.slack
        let known = session.activation
        let isPartial = known.map { session.start.timeIntervalSince($0) > slack } ?? true
        let activation = known.map { Swift.min($0, session.start) } ?? session.start
        let dataStart = isPartial ? session.start : activation
        let end = Swift.max(session.end, dataStart)
        let data = DateInterval(start: dataStart, end: end)
        return PatchSession(
            id: session.id.uuidString,
            plugin: session.plugin,
            kind: session.kind,
            activation: activation,
            isActivationKnown: known != nil,
            end: end,
            dataStart: dataStart,
            gaps: gaps(session.covered, in: DateInterval(start: dataStart, end: end)),
            isOpen: session.isOpen,
            coveredSeconds: StatsIntervals.intersect(session.covered, with: data).reduce(0) { $0 + $1.duration }
        )
    }

    /// The stretches of `span` outside the intervals, of `minimumGap` or longer.
    /// - Parameter covered: sorted, merged
    static func gaps(_ covered: [DateInterval], in span: DateInterval) -> [DateInterval] {
        var gaps: [DateInterval] = []
        var cursor = span.start
        for interval in covered where interval.end > span.start && interval.start < span.end {
            if interval.start > cursor {
                gaps.append(DateInterval(start: cursor, end: interval.start))
            }
            cursor = Swift.max(cursor, interval.end)
        }
        if cursor < span.end {
            gaps.append(DateInterval(start: cursor, end: span.end))
        }
        return gaps.filter { $0.duration >= minimumGap }
    }

    /// The topic's naming: the current pump's kind (its sessions: patches, pods, sites), without a pump the newest
    /// session's; nil without sessions (the topic isn't offered).
    /// - Parameter sessions: newest -> oldest
    static func topic(_ sessions: [PatchSession], currentPlugin: String?) -> PatchTopic? {
        guard let newest = sessions.first else { return nil }
        return PatchTopic(kind: currentPlugin.map { PatchKind(plugin: $0) } ?? newest.kind)
    }

    /// The patch in use: the open pump session of the plugin delivering now; nil while none delivers.
    /// - Parameter deliveringPlugin: the current pump's plugin while it has an active delivery unit
    ///   (`KnownPlugins.hasActiveDeliveryUnit`), otherwise nil
    static func inUse(_ sessions: [PatchSession], deliveringPlugin: String?) -> PatchSession? {
        guard let deliveringPlugin else { return nil }
        return sessions.first { $0.isOpen && $0.plugin == deliveringPlugin }
    }

    /// The sessions overlapping the window, each whole, newest -> oldest.
    static func pick(_ sessions: [PatchSession], overlapping window: DateInterval) -> [PatchSession] {
        sessions.filter { $0.end > window.start && $0.activation < window.end }
    }

    /// Today's comparison: the `previousCount` sessions of its plugin before `session` (older), those recorded whole
    /// (not partial) and worn at least `age` (one that ended sooner is left out), newest -> oldest.
    /// - Parameter sessions: newest -> oldest
    static func previous(_ sessions: [PatchSession], before session: PatchSession, age: TimeInterval) -> [PatchSession] {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return [] }
        return sessions.dropFirst(index + 1)
            .filter { $0.plugin == session.plugin }
            .prefix(previousCount)
            .filter { !$0.isPartial && $0.wear >= age }
    }

    /// The wear days to show: up to the longest session's last (at least 1).
    static func wearDayCount(_ sessions: [PatchSession]) -> Int {
        Swift.max(1, sessions.map { dayIndex(at: $0.wear) + 1 }.max() ?? 1)
    }

    /// The wear day an age is in, 0 for Day 1; an age at a day's end is still that day (a session of exactly 72 h has
    /// 3 days).
    static func dayIndex(at age: TimeInterval) -> Int {
        guard age > 0 else { return 0 }
        return Int((age / wearDay).rounded(.up)) - 1
    }

    /// The longest wear that sets the wear bars' scale: of the sessions worn at most `scaleWearLimit`; 0 without.
    static func scaleWear(_ sessions: [PatchSession]) -> TimeInterval {
        sessions.map(\.wear).filter { $0 <= scaleWearLimit }.max() ?? 0
    }

    /// A session's hours of age, the first first: each `[activation + k h, activation + (k + 1) h)` inside the data
    /// span, nil for an hour without time in it (before the recording's start).
    static func hours(of session: PatchSession) -> [DateInterval?] {
        let hour = TimeInterval.hours(1)
        let count = session.wear > 0 ? Int((session.wear / hour).rounded(.up)) : 0
        return (0 ..< count).map { index -> DateInterval? in
            let start = Swift.max(session.activation.addingTimeInterval(hour * Double(index)), session.dataStart)
            let end = Swift.min(session.activation.addingTimeInterval(hour * Double(index + 1)), session.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
    }

    // MARK: - Numbers

    /// The sessions' numbers from the read range's rows, in their order.
    /// - Parameters:
    ///   - input: covering the sessions' data spans (and the state running into them, the readings' lookback)
    ///   - inUseID: the patch in use's (`inUse`)
    static func stats(
        _ sessions: [PatchSession],
        input: PatchInput,
        bands: StatsBands,
        allowOneMinuteLoop: Bool,
        inUseID: String?,
        now: Date,
        calendar: Calendar
    ) -> [PatchStats] {
        guard let start = sessions.map(\.dataStart).min(), let end = sessions.map(\.end).max() else { return [] }
        let counter = Counter(
            input: input,
            window: DateInterval(start: start, end: Swift.max(start, end)),
            bands: bands,
            allowOneMinuteLoop: allowOneMinuteLoop,
            now: now,
            calendar: calendar
        )
        return sessions.map { session in
            let hours = Self.hours(of: session).map { $0.map { counter.numbers($0, loops: false) } ?? .zero }
            var whole = PatchNumbers.pooled(hours)
            let loops = counter.numbers(session.dataSpan, loops: true)
            whole.loopSlots = loops.loopSlots
            whole.loopSuccesses = loops.loopSuccesses
            return PatchStats(session: session, isInUse: session.id == inUseID, whole: whole, hours: hours)
        }
    }

    /// The wear days over the sessions: for each, the sessions' time in it pooled (the one in use in the days it
    /// reached), Day 1 first; only those with `minimumWearDayTime` in them. Only the sessions whose wear counts
    /// (`PatchSession.isWearCounted`): without a known activation its days count from its start, not its activation.
    static func byWearDay(_ stats: [PatchStats]) -> [PatchWearDay] {
        let known = stats.filter(\.session.isWearCounted)
        return pooledDays(known.map(\.wearDays), count: wearDayCount(known.map(\.session)))
    }

    /// Today's usual by wear day: the previous sessions' time in each day up to the age, pooled; the days up to the age.
    static func byWearDay(_ previous: [PatchStats], upTo age: TimeInterval) -> [PatchWearDay] {
        pooledDays(previous.map { $0.wearDays(upTo: age) }, count: dayIndex(at: age) + 1)
    }

    private static func pooledDays(_ sessions: [[PatchNumbers]], count: Int) -> [PatchWearDay] {
        (0 ..< count).compactMap { index -> PatchWearDay? in
            let pieces = sessions.compactMap { days -> PatchNumbers? in
                guard days.indices.contains(index), days[index].seconds > 0 else { return nil }
                return days[index]
            }
            let pooled = PatchNumbers.pooled(pieces)
            guard pooled.seconds >= minimumWearDayTime else { return nil }
            return PatchWearDay(index: index, sessions: pieces.count, numbers: pooled)
        }
    }

    /// The numbers of each interval counted directly (not summed from hours), loops left out: what the hours add up to.
    static func numbers(
        _ intervals: [DateInterval],
        input: PatchInput,
        bands: StatsBands,
        now: Date,
        calendar: Calendar
    ) -> [PatchNumbers] {
        guard let start = intervals.map(\.start).min(), let end = intervals.map(\.end).max() else { return [] }
        let counter = Counter(
            input: input,
            window: DateInterval(start: start, end: end),
            bands: bands,
            allowOneMinuteLoop: false,
            now: now,
            calendar: calendar
        )
        return intervals.map { counter.numbers($0, loops: false) }
    }

    // MARK: - Kept numbers

    /// A change of the stored rows touches a session's numbers: its interval meets the data span; a change without an
    /// interval touches them all. No reach of its own: the services publish their changes widened by theirs
    /// (`InsulinStatsService.Config.changeReach`, `GlucoseStatistics.Config.changeReach`), which covers the readings'
    /// cadence lookback and an IOB row's span.
    static func touches(_ change: DateInterval?, _ session: PatchSession) -> Bool {
        guard let change else { return true }
        return change.start <= session.end && session.dataStart <= change.end
    }

    /// The kept numbers that are still the sessions': of the same session now (its units, span and gaps), and not the
    /// patch in use (its time grows: always computed again), by id.
    static func reusable(_ kept: [String: PatchStats], for sessions: [PatchSession], inUseID: String?) -> [String: PatchStats] {
        var reusable: [String: PatchStats] = [:]
        for session in sessions where session.id != inUseID {
            if let stats = kept[session.id], stats.session == session, !stats.isInUse {
                reusable[session.id] = stats
            }
        }
        return reusable
    }

    /// Every session's numbers, in their order: the reusable ones as they are, `computed` for the others (none missing
    /// when `computed` has every session not reused).
    static func assembled(
        _ sessions: [PatchSession],
        reused: [String: PatchStats],
        computed: [PatchStats]
    ) -> [PatchStats] {
        let computed = Dictionary(computed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return sessions.compactMap { reused[$0.id] ?? computed[$0.id] }
    }

    // MARK: - Helpers

    /// The rows prepared once for every interval counted.
    private struct Counter {
        let segments: [DeliverySegment]
        /// oldest -> newest
        let boluses: [PumpEventRecord]
        let spans: [IOBSpan]
        let readings: [WeightedPoint]
        /// sorted
        let records: [HomeLoopStats.Record]
        /// sorted
        let readingTimes: [Date]
        let bands: StatsBands
        let allowOneMinuteLoop: Bool

        init(
            input: PatchInput,
            window: DateInterval,
            bands: StatsBands,
            allowOneMinuteLoop: Bool,
            now: Date,
            calendar: Calendar
        ) {
            let insulin = input.insulin
            segments = InsulinStatsEngine.timeline(
                events: insulin.events,
                coverage: insulin.coverage,
                schedules: insulin.schedules,
                window: window,
                now: now,
                calendar: calendar
            )
            boluses = InsulinStatsEngine.usableEvents(insulin.events, coverage: insulin.coverage)
                .filter { $0.kind == .bolus && $0.units > 0 && $0.date <= now }
            spans = InsulinStatsEngine.iobSpans(insulin.iob, now: now)
            let cleaned = GlucoseStatsEngine.clean(input.glucose)
            readings = GlucoseStatsEngine.weigh(cleaned)
            records = input.loops.sorted { $0.start < $1.start }
            readingTimes = cleaned.map(\.time)
            self.bands = bands
            self.allowOneMinuteLoop = allowOneMinuteLoop
        }

        func numbers(_ interval: DateInterval, loops: Bool) -> PatchNumbers {
            var numbers = PatchNumbers()
            numbers.seconds = interval.duration
            guard interval.duration > 0 else { return numbers }

            if loops {
                // the loops alone (the rest is summed from the hours)
                let slots = HomeLoopStats.Slots(HomeLoopStats.slots(
                    interval,
                    windowEnd: interval.end,
                    records: records,
                    readings: readingTimes,
                    allowOneMinuteLoop: allowOneMinuteLoop
                ))
                numbers.loopSlots = slots.count
                numbers.loopSuccesses = slots.successes
                return numbers
            }

            var index = segments.partitionIndex { $0.interval.end > interval.start }
            while index < segments.count, segments[index].interval.start < interval.end {
                let segment = segments[index]
                let seconds = StatsIntervals.overlap(segment.interval, interval)
                if seconds > 0 {
                    if segment.interval.duration > 0 {
                        numbers.basal += segment.amount * seconds / segment.interval.duration
                    }
                    if segment.isCovered {
                        numbers.coveredSeconds += seconds
                    }
                }
                index += 1
            }

            index = boluses.partitionIndex { $0.date >= interval.start }
            while index < boluses.count, boluses[index].date < interval.end {
                let bolus = boluses[index]
                if bolus.isExternal {
                    numbers.external += bolus.units
                } else if bolus.isSMB {
                    numbers.smb += bolus.units
                } else {
                    numbers.bolus += bolus.units
                }
                index += 1
            }

            index = spans.partitionIndex { $0.interval.end > interval.start }
            while index < spans.count, spans[index].interval.start < interval.end {
                let seconds = StatsIntervals.overlap(spans[index].interval, interval)
                numbers.iobSeconds += seconds
                if spans[index].isNegative {
                    numbers.negativeIOBSeconds += seconds
                }
                index += 1
            }

            let histogram = GlucoseStatsEngine.histogram(readings, clippedTo: interval)
            numbers.glucoseSeconds = histogram.totalSeconds
            numbers.bandSeconds = GlucoseBand.allCases.map { GlucoseStatsEngine.seconds(histogram, in: $0, bands: bands) }
            if let mean = histogram.mean, let sd = histogram.sd {
                numbers.glucoseSum = mean * histogram.totalSeconds
                numbers.glucoseSquares = (sd * sd + mean * mean) * histogram.totalSeconds
            }
            return numbers
        }
    }
}
