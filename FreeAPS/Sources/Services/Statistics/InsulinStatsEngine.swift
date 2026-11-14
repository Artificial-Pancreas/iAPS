import Foundation

/// A `Reasons` row as the statistics use it: the loop's IOB at that time, U.
struct IOBPoint: Sendable, Equatable {
    let time: Date
    let iob: Double
}

/// The time an IOB row stands for (`InsulinStatsEngine.iobSpans`), and its IOB.
struct IOBSpan: Sendable, Equatable {
    let interval: DateInterval
    /// U
    let iob: Double

    var isNegative: Bool { iob < 0 }
}

/// A day's IOB as the IOB cards use it (`DayInsulin.iob`): its 15-minute means by the clock and its lowest below zero.
struct DayIOB: Sendable, Equatable {
    /// The lowest IOB below zero of a day.
    struct Lowest: Sendable, Equatable {
        /// U
        let iob: Double
        /// the row's own time (before midnight for a row running over it)
        let at: Date
    }

    static let binMinutes = 15
    static let binCount = 24 * 60 / binMinutes

    /// by the local clock's quarter hour (0...95): the IOB rows' mean over the time they stand for, U; nil without IOB
    /// time in it (today after now, the skipped hour of a spring-forward day; the repeated hour holds both passes)
    let bins: [Double?]
    /// the first of equals; nil without negative IOB
    let lowest: Lowest?
    /// U·s: Σ IOB × seconds over the time below zero; over `DayInsulin.negativeIOBSeconds`, the mean depth
    let negativeArea: Double

    static let empty = DayIOB(bins: Array(repeating: nil, count: binCount), lowest: nil, negativeArea: 0)
}

/// The IOB by time of day over days (`InsulinStatsEngine.iobProfile`): a 15-minute bin's percentiles, U.
struct IOBProfileBin: Sendable, Equatable {
    let p10: Double
    let p25: Double
    let p50: Double
    let p75: Double
    let p90: Double
}

/// The Negative IOB card's numbers over the headline days (`InsulinStatsEngine.negativeIOB`).
struct NegativeIOBSummary: Sendable, Equatable {
    let headlineDays: Int
    /// seconds per day of IOB time (`InsulinSummary.negativeIOBSecondsPerDay`); nil without IOB rows
    let secondsPerDay: Double?
    /// of the IOB time, 0...1; nil without IOB rows
    let share: Double?
    /// U: the mean IOB over the time below zero; nil without it
    let meanDepth: Double?
    /// U and when: the lowest IOB below zero (the row's own time) and the index of its day in the days given; nil
    /// without it
    let lowest: Double?
    let lowestAt: Date?
    let lowestDay: Int?
    /// seconds per day of IOB time in each clock hour, 0...23 (they sum to `secondsPerDay`); nil without IOB rows
    let hours: [Double]?
    /// the IOB time of the headline days' time, 0...1; 0 without a headline day
    let iobCoverage: Double

    /// The IOB rows don't cover the headline days (the pump data's rule, `InsulinSummary.coveragePercent` below 100):
    /// the card's numbers are provisional.
    var isIOBLimited: Bool { headlineDays > 0 && Int((iobCoverage * 100).rounded()) < 100 }
}

/// A piece of the delivery timeline (`InsulinStatsEngine.timeline`): `[start, end)` with one cause, inside one clock
/// hour of one calendar day, and inside or outside coverage as a whole.
struct DeliverySegment: Sendable, Equatable {
    enum Cause: Sendable, Equatable {
        case temp
        /// covered time without a temp or a suspension: the schedule in effect
        case scheduled
        case suspended
    }

    let interval: DateInterval
    let cause: Cause
    /// U/h: the temp's rate, the schedule's, 0 suspended
    let rate: Double
    /// U delivered in the segment (a final temp's share of its delivered units)
    let amount: Double
    /// inside coverage: counts in the covered time and the scheduled amount
    let isCovered: Bool
    /// U/h of the schedule in effect; 0 outside coverage
    let scheduledRate: Double
    /// covered, and before the oldest schedule record: the oldest one is used
    let profileAssumed: Bool

    /// U the schedule in effect gives the segment; 0 outside coverage
    var scheduledAmount: Double { isCovered ? scheduledRate * interval.duration / .hours(1) : 0 }
    /// covered time at rate 0: suspended, a zero temp, a zero schedule entry
    var isZeroBasal: Bool { isCovered && rate == 0 }
}

/// What the insulin statistics read for a range of days (the service's fetches, §3.1 of the plan).
struct InsulinInput: Sendable, Equatable {
    /// the events of the range, both sources, plus the state running into it (the newest suspend, resume and temp
    /// before it); no coverage rows
    var events: [PumpEventRecord]
    /// the covered time touching the range, both sources, and the pump's local time in it (`isCovered == false`)
    /// (`CoreDataStorage.fetchCoverage`: the pump sessions', `PumpSessionRules.localTime`)
    var coverage: [CoveredInterval]
    /// the schedule records of the range, plus the newest one before it (or, without one, the oldest record)
    var schedules: [BasalScheduleRecordValue]
    /// the `Reasons` rows of the range
    var iob: [IOBPoint]

    init(
        events: [PumpEventRecord] = [],
        coverage: [CoveredInterval] = [],
        schedules: [BasalScheduleRecordValue] = [],
        iob: [IOBPoint] = []
    ) {
        self.events = events
        self.coverage = coverage
        self.schedules = schedules
        self.iob = iob
    }
}

/// A clock hour of a day (`DayInsulin.hours`). Additive: the hours of a day sum to the day.
struct HourInsulin: Sendable, Equatable {
    /// 0...23, by the local clock: the repeated hour of the 25-hour day holds two hours, the skipped one of the
    /// 23-hour day none
    let hour: Int
    /// U, every segment (temps outside coverage too)
    var basal: Double = 0
    var smb: Double = 0
    var bolus: Double = 0
    /// U the schedules in effect give the covered time
    var scheduled: Double = 0
    var zeroBasalSeconds: Double = 0
    var coveredSeconds: Double = 0
    var negativeIOBSeconds: Double = 0
    var iobSeconds: Double = 0

    init(hour: Int) {
        self.hour = hour
    }

    fileprivate mutating func add(_ segment: DeliverySegment) {
        basal += segment.amount
        scheduled += segment.scheduledAmount
        if segment.isCovered {
            coveredSeconds += segment.interval.duration
        }
        if segment.isZeroBasal {
            zeroBasalSeconds += segment.interval.duration
        }
    }
}

/// A bolus of a day (`DayInsulin.boluses`): the Insulin tab's Today lists today's, Good & bad days pairs the past
/// days' with the meals.
struct InsulinBolus: Sendable, Equatable {
    let date: Date
    /// U
    let units: Double
    let isSMB: Bool
    /// External Insulin (a pen), not the pump's
    let isExternal: Bool
}

/// A calendar day of the Insulin tab (`InsulinStatsEngine.days`). Today is computed up to `now`.
struct DayInsulin: Sendable, Equatable {
    /// the whole calendar day (23, 24 or 25 h), also today's
    let day: DateInterval
    let isToday: Bool
    /// U, every segment (temps outside coverage too)
    let basal: Double
    /// U of the SMBs starting in the day
    let smb: Double
    /// U of the other boluses starting in the day, External Insulin included
    let bolus: Double
    /// U the schedules in effect give the covered time
    let scheduled: Double
    /// covered time at rate 0
    let zeroBasalSeconds: Double
    let coveredSeconds: Double
    let negativeIOBSeconds: Double
    /// the time the IOB rows stand for
    let iobSeconds: Double
    /// its 15-minute means and runs below zero (the IOB cards)
    let iob: DayIOB
    /// 24, by `hour`
    let hours: [HourInsulin]
    /// a bolus starts in it, or a temp runs in it
    let hasDeliveries: Bool
    /// the end of its last covered time (the last heartbeat for today)
    let coveredUntil: Date?
    /// when some covered time is before the oldest schedule record: that record's date
    let profileAssumedBefore: Date?
    /// the boluses, oldest -> newest: today's all (the SMBs too); a past day's (cached) only those that aren't SMBs
    /// (`PumpEventRecord.isSMB`), a few a day: Good & bad days' late or no bolus
    let boluses: [InsulinBolus]

    /// covered time, or a bolus or a temp: without, "No pump data"
    var hasData: Bool { coveredSeconds > 0 || hasDeliveries }
    /// of the whole day
    var coverageFraction: Double { day.duration > 0 ? coveredSeconds / day.duration : 0 }
    var profileAssumed: Bool { profileAssumedBefore != nil }
    /// U, as delivered: today "so far"
    var total: Double { basal + smb + bolus }
    /// In the headline averages (rule a): a past day with at least `InsulinStatsEngine.headlineCoverage` covered.
    var isHeadline: Bool { !isToday && coverageFraction >= InsulinStatsEngine.headlineCoverage }
    /// The basal scaled to the whole day by its covered time (a day with a 3 h gap isn't low); the boluses are not.
    var scaledBasal: Double { coveredSeconds > 0 ? basal * day.duration / coveredSeconds : basal }
    /// basal / scheduled; nil at 0 scheduled
    var basalVsScheduled: Double? { scheduled > 0 ? basal / scheduled : nil }
    /// U: the scaled basal (`scaledBasal`) and the boluses as delivered, the day's TDD (`InsulinSummary.tdd` is their
    /// mean over the headline days)
    var scaledTotal: Double { scaledBasal + smb + bolus }

    /// U by the clock hour (0...23) and the share of it passed (0...1), as `InsulinStatsEngine.clockAverage` counts a
    /// day: the hours before it in full, its own prorated by the share (the hours hold no times within them), the basal
    /// scaled as `scaledBasal` (the same factor every hour), the boluses as delivered. By the end of the day,
    /// `scaledTotal`; the mean over the headline days is `clockAverage`'s `value(hour:passed:)`.
    func scaledInsulin(hour: Int, passed: Double) -> Double {
        insulin(hour: hour, passed: passed, basalFactor: coveredSeconds > 0 ? day.duration / coveredSeconds : 1)
    }

    /// U by the clock hour and the share of it passed as `scaledInsulin(hour:passed:)`, but as delivered (the basal not
    /// scaled): a day out of the headline averages (Home's insulin card draws it as delivered). By the end of the day,
    /// `total`.
    func deliveredInsulin(hour: Int, passed: Double) -> Double {
        insulin(hour: hour, passed: passed, basalFactor: 1)
    }

    /// the hours before `hour` in full, `hour` by the share, the basal × `basalFactor`
    private func insulin(hour: Int, passed: Double, basalFactor: Double) -> Double {
        let share = Swift.min(Swift.max(passed, 0), 1)
        return hours.reduce(0) { total, h in
            let weight: Double = h.hour < hour ? 1 : h.hour == hour ? share : 0
            return total + (h.basal * basalFactor + h.smb + h.bolus) * weight
        }
    }
}

/// The Insulin tab's headline numbers (`InsulinStatsEngine.summary`), rule (a): the means over the headline days.
struct InsulinSummary: Sendable, Equatable {
    /// from the first day's start to the last day's end
    let window: DateInterval
    /// N: the period's days, today included
    let calendarDays: Int
    /// "Pump data on n of N days"
    let daysWithData: Int
    /// the past days with at least half of them covered
    let headlineDays: Int
    /// U per day, nil without a headline day ("Needs one complete day")
    let tdd: Double?
    /// U per day: the scaled basal, the SMBs and the boluses, means over the headline days
    let basal: Double?
    let smb: Double?
    let bolus: Double?
    /// basal, SMB, bolus; largest remainder, sums to 100 (all 0 without a headline day or insulin)
    let splitPercents: [Int]
    /// Σ basal / Σ scheduled over the headline days; nil at 0 scheduled
    let basalVsScheduled: Double?
    /// U per day of covered time: Σ scheduled / Σ covered × 24 h
    let scheduledPerDay: Double?
    /// seconds per day of covered time: Σ zero basal / Σ covered × 24 h
    let zeroBasalSecondsPerDay: Double?
    /// seconds per day of IOB rows: Σ negative / Σ IOB seconds × 24 h; nil without IOB rows
    let negativeIOBSecondsPerDay: Double?
    /// Σ covered / (the last covered moment − window start), 0...1
    let coverage: Double
    /// the rounded value is the one used for display AND for the limited test
    let coveragePercent: Int
    /// no covered time and no bolus or temp in the period: "No pump data in this period"
    let isEmpty: Bool
    /// a headline day used the oldest schedule for time before it: that record's date
    let profileAssumedBefore: Date?

    /// "Pump data on n of N days · c% coverage"
    var isLimited: Bool { headlineDays < calendarDays - 1 || coveragePercent < 100 }
    /// the headline shows "–" with "Needs one complete day"
    var needsCompleteDay: Bool { tdd == nil }
    /// plain rounding; nil at 0 scheduled ("–")
    var basalVsScheduledPercent: Int? { basalVsScheduled.map { Int(($0 * 100).rounded()) } }
}

/// A clock hour of the By-hour chart (`InsulinStatsEngine.hours`), over the headline days.
struct InsulinHourSummary: Sendable, Equatable {
    let hour: Int
    /// the headline days
    let days: Int
    /// "{h} hours of data": the covered seconds in this clock hour over the headline days, in hours
    let coveredHours: Double
    /// U per hour (per covered hour); nil without covered time
    let basal: Double?
    let scheduled: Double?
    /// seconds at zero basal per covered hour; nil without covered time
    let zeroBasalSeconds: Double?
    /// U per day in this hour (not extrapolated, like the headline)
    let smb: Double
    let bolus: Double
    /// Σ basal / Σ scheduled; nil at 0 scheduled
    let basalVsScheduled: Double?

    /// U: basal (0 without covered time) + SMB + bolus
    var total: Double { (basal ?? 0) + smb + bolus }
}

/// The usual by 14:35 (Home's insulin card's tick, the Insulin tab's Today) at every clock time of a day
/// (`InsulinStatsEngine.clockAverage`), U: the total, and its basal, SMB and bolus (the Insulin tab's Today), with the
/// negative IOB time.
struct InsulinClockAverage: Sendable, Equatable {
    /// One quantity's mean by the clock time.
    struct Series: Sendable, Equatable {
        /// by the start of each clock hour, 0...23
        let before: [Double]
        /// in each clock hour, 0...23
        let within: [Double]

        /// - Parameter within: in each clock hour, 0...23
        init(within: [Double]) {
            var before: [Double] = []
            var total = 0.0
            for value in within {
                before.append(total)
                total += value
            }
            self.before = before
            self.within = within
        }

        /// By the clock hour (0...23) and the share of it passed (0...1).
        func value(hour: Int, passed: Double) -> Double {
            guard before.indices.contains(hour), within.indices.contains(hour) else { return 0 }
            return before[hour] + within[hour] * Swift.min(Swift.max(passed, 0), 1)
        }

        /// By the local clock time of `date`.
        func value(at date: Date, calendar: Calendar) -> Double {
            let clock = InsulinClockAverage.clock(of: date, calendar: calendar)
            return value(hour: clock.hour, passed: clock.passed)
        }
    }

    /// basal (scaled as the total's), SMB, bolus: `InsulinPart`'s order; in each hour they sum to `total`'s
    let parts: [Series]
    /// U
    let total: Series
    /// seconds with a negative IOB, per day of IOB time (`InsulinSummary.negativeIOBSecondsPerDay`'s rule); nil without
    /// IOB rows
    let negativeIOBSeconds: Series?

    /// the total by the start of each clock hour, 0...23
    var before: [Double] { total.before }
    /// the total in each clock hour, 0...23
    var within: [Double] { total.within }

    /// The total by the clock hour (0...23) and the share of it passed (0...1).
    func value(hour: Int, passed: Double) -> Double {
        total.value(hour: hour, passed: passed)
    }

    /// The total by the local clock time of `date`.
    func value(at date: Date, calendar: Calendar) -> Double {
        total.value(at: date, calendar: calendar)
    }

    /// Basal, SMB, bolus by the local clock time of `date`: they sum to `value(at:calendar:)`.
    func parts(at date: Date, calendar: Calendar) -> [Double] {
        parts.map { $0.value(at: date, calendar: calendar) }
    }

    /// The local clock hour (0...23) of `date` and the share of it passed, to the second.
    static func clock(of date: Date, calendar: Calendar) -> (hour: Int, passed: Double) {
        let clock = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Swift.min(Swift.max(clock.hour ?? 0, 0), 23)
        let seconds = Double(clock.minute ?? 0) * 60 + Double(clock.second ?? 0)
        return (hour, seconds / .hours(1))
    }
}

/// One request's result for the Insulin tab.
struct InsulinPeriod: Sendable, Equatable {
    let summary: InsulinSummary
    /// oldest -> newest, the last one today
    let days: [DayInsulin]
    /// 24, by hour
    let hours: [InsulinHourSummary]
}

/// The insulin statistics, as pure functions: no Core Data, no `Date()`, no global calendar (`now` and `calendar` are
/// always parameters). Units are standard (U100-equivalent) throughout, as the store holds them (D7).
///
/// **Scheduled basal and autotune.** "Scheduled" is the pump's own programmed schedule, the basal schedule history as
/// recorded from `basal_profile.json`, also with `useAutotune` on. That is what the pump delivers without a temp, so
/// it is the right fill for the delivered insulin, and "vs scheduled" compares the delivery with what the pump would
/// have given on its own. With autotune the loop's neutral temps follow the autotuned basal, so "vs scheduled" then
/// also shows autotune's difference from the pump schedule. The autotuned basal itself is not stored over time
/// (`autotune.json` holds only the latest result, replaced by every run), so a comparison with it would need its own
/// history: not done here.
enum InsulinStatsEngine {
    /// A past day is in the headline averages from this share of it covered (rule a).
    static let headlineCoverage = 0.5
    /// The days before today the usual by now is over (Statistics › Insulin › Today, `InsulinStatsService.today`, and
    /// Home's insulin card): the complete ones among them, labelled "7 d".
    static let usualDays = 7
    /// `Reasons` rows closer than this are one (a failed loop's row next to the next loop's).
    static let iobDuplicateWindow: TimeInterval = .seconds(10)
    /// A row stands for the time up to the next one when that is at most this far ...
    static let iobMaximumSpan: TimeInterval = .minutes(7.5)
    /// ... otherwise, and for the newest row, for this long.
    static let iobDefaultSpan: TimeInterval = .minutes(5)

    // MARK: - Sources

    /// The events to count, sorted by (date, kind, source): a Nightscout event with a pump event of the same identity, or
    /// inside the pump's local time (the `pump` entries of the coverage: `PumpSessionRules.localTime`, both ends, the
    /// store's own rule), dropped, so the two sources never double count; a second row of one identity and source
    /// dropped.
    static func usableEvents(_ events: [PumpEventRecord], coverage: [CoveredInterval]) -> [PumpEventRecord] {
        let pumpIdentities = Set(events.filter { $0.source == .pump }.map(\.identity))
        let local = PumpSessionRules.mergedClosed(coverage.filter { $0.source == .pump }.map(\.interval))
        var seen = Set<SourcedIdentity>()
        return events
            .filter { event in
                guard event.source == .nightscout else { return true }
                return !pumpIdentities.contains(event.identity) && !PumpSessionRules.isLocal(event.date, in: local)
            }
            .sorted { ($0.date, $0.kind.rawValue, $0.source.rawValue) < ($1.date, $1.kind.rawValue, $1.source.rawValue) }
            .filter { seen.insert(SourcedIdentity(identity: $0.identity, source: $0.source)).inserted }
    }

    /// The covered time (both sources) as sorted, merged intervals; the local time's pieces that cover nothing
    /// (`CoveredInterval.isCovered == false`) left out.
    static func coveredIntervals(_ coverage: [CoveredInterval]) -> [DateInterval] {
        StatsIntervals.mergedDroppingEmpty(coverage.filter(\.isCovered).map(\.interval))
    }

    // MARK: - Delivery timeline

    /// The delivery timeline of the window up to `now`, oldest -> newest, back to back where something is known:
    /// - **suspended** (rate 0) from a suspend to the earliest of the next resume, the next pump delivery (a bolus that
    ///   isn't External Insulin, a temp start) and `now`, also across coverage gaps (zero basal only where covered).
    ///   A suspension wins over a temp running through it;
    /// - **temp**, counted wherever it is (an explicit delivery), from its start to the earliest of its nominal end
    ///   (`PumpEventRecord.nominalDuration`), the next temp's start, a suspension and `now`. A final with delivered
    ///   units counts them in full, unless a suspension clips it (`units × kept / nominal`); otherwise `rate × span`;
    /// - **scheduled**: covered time without either, at the rate of the schedule in effect (the newest record at or
    ///   before the moment; before the oldest one the oldest, flagged `profileAssumed`), looked up by the local clock.
    ///
    /// Segments are split at midnight, at every clock hour, at every schedule record and at the schedule entries' clock
    /// times (both passes of the repeated hour of a DST change; the skipped hour has none), at the coverage boundaries
    /// and at every event, so days and hours are additive. Uncovered time without a temp or a suspension has no segment.
    /// Without any schedule record nothing is covered (nothing to fill with); temps and suspensions still count.
    /// - Parameter events: the window's, plus the state running into it; any order, Nightscout duplicates included
    static func timeline(
        events: [PumpEventRecord],
        coverage: [CoveredInterval],
        schedules: [BasalScheduleRecordValue],
        window: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [DeliverySegment] {
        let end = Swift.min(window.end, now)
        guard end > window.start else { return [] }
        let days = StatsClock.calendarDays(in: DateInterval(start: window.start, end: end), calendar: calendar)
        return timeline(
            usable: usableEvents(events, coverage: coverage),
            coverage: coverage,
            schedules: Schedules(schedules),
            days: days,
            slots: hourSlots(days, timeZone: calendar.timeZone),
            range: DateInterval(start: window.start, end: end),
            now: now,
            timeZone: calendar.timeZone
        )
    }

    // MARK: - IOB

    /// The time each `Reasons` row stands for, oldest -> newest: rows sorted and deduplicated within
    /// `iobDuplicateWindow` (the first kept); a row stands for the time up to the next one when that is at most
    /// `iobMaximumSpan` away, otherwise for `iobDefaultSpan`; the newest for `iobDefaultSpan` but not past `now`.
    static func iobSpans(_ points: [IOBPoint], now: Date) -> [IOBSpan] {
        var rows: [IOBPoint] = []
        for point in points.sorted(by: { ($0.time, $0.iob) < ($1.time, $1.iob) }) where point.iob.isFinite {
            if let last = rows.last, point.time.timeIntervalSince(last.time) < iobDuplicateWindow {
                continue
            }
            rows.append(point)
        }
        return rows.indices.compactMap { index -> IOBSpan? in
            let row = rows[index]
            let span: TimeInterval
            if index + 1 < rows.count {
                let delta = rows[index + 1].time.timeIntervalSince(row.time)
                span = delta <= iobMaximumSpan ? delta : iobDefaultSpan
            } else {
                span = Swift.min(iobDefaultSpan, now.timeIntervalSince(row.time))
            }
            guard span > 0 else { return nil }
            return IOBSpan(interval: DateInterval(start: row.time, duration: span), iob: row.iob)
        }
    }

    // MARK: - Days

    /// The days of a request, oldest -> newest, each the whole calendar day; today (the day of `now`) is computed up
    /// to `now`. The days need not be back to back (the service reads runs of missing days).
    /// - Parameter days: whole calendar days, oldest -> newest
    static func days(_ days: [DateInterval], input: InsulinInput, now: Date, calendar: Calendar) -> [DayInsulin] {
        guard let first = days.first, let last = days.last else { return [] }
        let timeZone = calendar.timeZone
        let today = calendar.startOfDay(for: now)
        let slots = hourSlots(days, timeZone: timeZone)
        let usable = usableEvents(input.events, coverage: input.coverage)
        let schedules = Schedules(input.schedules)
        let range = DateInterval(start: first.start, end: Swift.max(first.start, Swift.min(last.end, now)))
        let segments = range.duration > 0
            ? timeline(
                usable: usable,
                coverage: input.coverage,
                schedules: schedules,
                days: days,
                slots: slots,
                range: range,
                now: now,
                timeZone: timeZone
            )
            : []

        var builders = days.map { DayBuilder(day: $0) }
        // segments: each inside one slot
        var slotIndex = 0
        for segment in segments {
            while slotIndex < slots.count, slots[slotIndex].interval.end <= segment.interval.start {
                slotIndex += 1
            }
            guard slotIndex < slots.count, slots[slotIndex].interval.start <= segment.interval.start else { continue }
            let slot = slots[slotIndex]
            builders[slot.day].add(segment, hour: slot.hour, assumedBefore: schedules.oldest)
        }
        // boluses at their timestamp, in full, wherever they are; none after now
        for event in usable where event.kind == .bolus && event.units > 0 && event.date <= now {
            guard let slot = self.slot(containing: event.date, in: slots) else { continue }
            builders[slot.day].add(bolus: event, hour: slot.hour)
        }
        // IOB rows, split at midnight and the clock hours
        let spans = iobSpans(input.iob, now: now)
        for span in spans {
            var index = firstSlot(endingAfter: span.interval.start, in: slots)
            while index < slots.count, slots[index].interval.start < span.interval.end {
                let slot = slots[index]
                let seconds = StatsIntervals.overlap(span.interval, slot.interval)
                if seconds > 0 {
                    builders[slot.day].add(iobSeconds: seconds, negative: span.isNegative, hour: slot.hour)
                    let piece = DateInterval(
                        start: Swift.max(span.interval.start, slot.interval.start),
                        end: Swift.min(span.interval.end, slot.interval.end)
                    )
                    builders[slot.day].add(
                        iob: span.iob,
                        over: piece,
                        rowStart: span.interval.start,
                        hour: slot.hour,
                        hourStart: slot.interval.start
                    )
                }
                index += 1
            }
        }
        return builders.map { $0.build(isToday: $0.day.start == today) }
    }

    /// The whole calendar days of a period, oldest -> newest, the last one today (`GlucoseStatsEngine.days(for:...)`
    /// unclipped: 23, 24 or 25 h each).
    /// For the N-day periods only (the Insulin and Meals tabs compute 7/14/30/90 d): Today and 24 h have no
    /// `calendarDayCount` and get the whole days touching the window, so 24 h gives all of yesterday (a possible headline
    /// day) and today. Callers map those to the nearest valid period first.
    static func periodDays(_ period: StatsPeriod, now: Date, calendar: Calendar) -> [DateInterval] {
        let window = GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar)
        return GlucoseStatsEngine.days(for: period, window: window, calendar: calendar).map { day in
            let start = calendar.startOfDay(for: day.start)
            return DateInterval(start: start, end: StatsClock.endOfDay(start, calendar: calendar))
        }
    }

    /// The last `count` whole calendar days (23, 24 or 25 h), oldest -> newest, the last one today: `periodDays` of an
    /// N-day period of `count` days, for any count (Today reads `usualDays + 1`: the 7 days before today, and today).
    static func lastDays(_ count: Int, now: Date, calendar: Calendar) -> [DateInterval] {
        let today = calendar.startOfDay(for: now)
        return (0 ..< Swift.max(count, 0)).reversed().map { back in
            let start = StatsClock.dayStart(back, before: today, calendar: calendar)
                ?? today.addingTimeInterval(-.days(back))
            return DateInterval(start: start, end: StatsClock.endOfDay(start, calendar: calendar))
        }
    }

    // MARK: - Summary

    /// The headline numbers, rule (a): the headline days are the past days with at least `headlineCoverage` covered
    /// (today never); on each the basal is scaled to the whole day (`DayInsulin.scaledBasal`) and the boluses are
    /// counted as delivered. TDD and the split are means over them; basal vs scheduled, scheduled, zero basal and
    /// negative IOB are their sums, per day of covered (IOB) time. Coverage is over the whole period up to the last
    /// covered moment.
    /// - Parameter days: `days(periodDays(period, ...), ...)`
    static func summary(_ days: [DayInsulin], period: StatsPeriod?) -> InsulinSummary {
        let start = days.first?.day.start ?? .distantPast
        let window = DateInterval(start: start, end: Swift.max(start, days.last?.day.end ?? start))
        let headline = days.filter(\.isHeadline)
        let count = Double(headline.count)

        func mean(_ value: (DayInsulin) -> Double) -> Double? {
            headline.isEmpty ? nil : headline.reduce(0) { $0 + value($1) } / count
        }
        func sum(_ value: (DayInsulin) -> Double) -> Double {
            headline.reduce(0) { $0 + value($1) }
        }

        let basal = mean(\.scaledBasal)
        let smb = mean(\.smb)
        let bolus = mean(\.bolus)
        let tdd = basal.map { $0 + (smb ?? 0) + (bolus ?? 0) }
        let covered = sum(\.coveredSeconds)
        let scheduled = sum(\.scheduled)
        let iobSeconds = sum(\.iobSeconds)
        let day = TimeInterval.hours(24)

        let coveredUntil = days.compactMap(\.coveredUntil).max()
        let reach = coveredUntil.map { $0.timeIntervalSince(window.start) } ?? 0
        let coverage = reach > 0 ? Swift.min(days.reduce(0) { $0 + $1.coveredSeconds } / reach, 1) : 0

        return InsulinSummary(
            window: window,
            calendarDays: period?.calendarDayCount ?? days.count,
            daysWithData: days.filter(\.hasData).count,
            headlineDays: headline.count,
            tdd: tdd,
            basal: basal,
            smb: smb,
            bolus: bolus,
            splitPercents: GlucoseStatsEngine.largestRemainder([basal ?? 0, smb ?? 0, bolus ?? 0]),
            basalVsScheduled: scheduled > 0 ? sum(\.basal) / scheduled : nil,
            scheduledPerDay: covered > 0 ? scheduled / covered * day : nil,
            zeroBasalSecondsPerDay: covered > 0 ? sum(\.zeroBasalSeconds) / covered * day : nil,
            negativeIOBSecondsPerDay: iobSeconds > 0 ? sum(\.negativeIOBSeconds) / iobSeconds * day : nil,
            coverage: coverage,
            coveragePercent: Int((coverage * 100).rounded()),
            isEmpty: !days.contains(where: \.hasData),
            profileAssumedBefore: headline.compactMap(\.profileAssumedBefore).max()
        )
    }

    /// The By-hour chart, over the headline days: basal, scheduled and zero basal per covered hour of each clock hour
    /// (the 25-hour day's repeated hour counts twice, the 23-hour day's skipped one not at all); SMB and bolus per
    /// headline day, not extrapolated.
    static func hours(_ days: [DayInsulin]) -> [InsulinHourSummary] {
        let headline = days.filter(\.isHeadline)
        return (0 ..< 24).map { hour in
            var sum = HourInsulin(hour: hour)
            for day in headline where day.hours.indices.contains(hour) {
                let h = day.hours[hour]
                sum.basal += h.basal
                sum.smb += h.smb
                sum.bolus += h.bolus
                sum.scheduled += h.scheduled
                sum.zeroBasalSeconds += h.zeroBasalSeconds
                sum.coveredSeconds += h.coveredSeconds
            }
            let coveredHours = sum.coveredSeconds / .hours(1)
            return InsulinHourSummary(
                hour: hour,
                days: headline.count,
                coveredHours: coveredHours,
                basal: coveredHours > 0 ? sum.basal / coveredHours : nil,
                scheduled: coveredHours > 0 ? sum.scheduled / coveredHours : nil,
                zeroBasalSeconds: coveredHours > 0 ? sum.zeroBasalSeconds / coveredHours : nil,
                smb: headline.isEmpty ? 0 : sum.smb / Double(headline.count),
                bolus: headline.isEmpty ? 0 : sum.bolus / Double(headline.count),
                basalVsScheduled: sum.scheduled > 0 ? sum.basal / sum.scheduled : nil
            )
        }
    }

    /// The usual by 14:35 (Home's tick, the Insulin tab's Today) for every clock time: the mean over the headline days
    /// (`DayInsulin.isHeadline`, so never today) of the insulin each had by that local clock time
    /// (`DayInsulin.scaledInsulin(hour:passed:)`), its basal scaled as the TDD's (`DayInsulin.scaledBasal`: by the whole
    /// day's covered time, the same factor for every hour), the boluses as delivered. So by the end of the day it is
    /// the period's TDD (`summary(...).tdd`), and a partly covered day isn't low by now. The clock hours before the time
    /// count in full; its own hour by the share of it that has passed: the hours hold no times within them (the cache
    /// keeps only them), so its insulin, a bolus in it too, is prorated by the minutes.
    ///
    /// DST: by clock hour, as `hours`. A 25-hour (fall-back) day's repeated hour holds both passes, so from that hour
    /// on that day counts an hour more by the clock time (13 h of basal by 12:00; within the repeated hour itself both
    /// passes are prorated together by the minutes); a 23-hour (spring-forward) day has nothing in the skipped hour, so
    /// it counts an hour less from there on (11 h by 12:00). Both end at the day's own (scaled) total: a one-day
    /// artefact of the average for the week after the change, left as is.
    ///
    /// The parts (the Insulin tab's Today) are the same means of each: the basal scaled, the SMBs and the boluses as
    /// delivered, so in every hour they sum to the total. The negative IOB time is the summary's rule by the clock time:
    /// the headline days' negative IOB seconds by then over all their IOB time, per day of it, so by the end of the day
    /// it is `summary(...).negativeIOBSecondsPerDay` (nil without IOB rows).
    /// - Parameter days: Today's, `days(lastDays(usualDays + 1, ...), ...)` (the 7 days before today, and today), or a
    ///   period's
    static func clockAverage(_ days: [DayInsulin]) -> InsulinClockAverage? {
        let headline = days.filter(\.isHeadline)
        guard headline.isNotEmpty else { return nil }
        var basal = [Double](repeating: 0, count: 24)
        var smb = basal
        var bolus = basal
        var negative = basal
        var iobSeconds = 0.0
        for day in headline {
            let factor = day.coveredSeconds > 0 ? day.day.duration / day.coveredSeconds : 1
            for h in day.hours where basal.indices.contains(h.hour) {
                basal[h.hour] += h.basal * factor
                smb[h.hour] += h.smb
                bolus[h.hour] += h.bolus
                negative[h.hour] += h.negativeIOBSeconds
            }
            iobSeconds += day.iobSeconds
        }
        let count = Double(headline.count)
        let parts = [basal, smb, bolus].map { sums in InsulinClockAverage.Series(within: sums.map { $0 / count }) }
        let total = InsulinClockAverage.Series(within: (0 ..< 24).map { hour in
            parts.reduce(0) { $0 + $1.within[hour] }
        })
        return InsulinClockAverage(
            parts: parts,
            total: total,
            negativeIOBSeconds: iobSeconds > 0
                ? InsulinClockAverage.Series(within: negative.map { $0 / iobSeconds * .hours(24) })
                : nil
        )
    }

    /// The whole computation of a period from its raw input: its days, the summary and the hours.
    static func period(_ period: StatsPeriod, input: InsulinInput, now: Date, calendar: Calendar) -> InsulinPeriod {
        let days = days(periodDays(period, now: now, calendar: calendar), input: input, now: now, calendar: calendar)
        return InsulinPeriod(summary: summary(days, period: period), days: days, hours: hours(days))
    }

    // MARK: - IOB cards

    /// The IOB card's percentile bands (and Today's usual) need this many headline days; with fewer the days are lines.
    static let iobProfileMinimumDays = 3

    /// The Negative IOB card over the headline days (`DayInsulin.isHeadline`): the summary's time per day and its share
    /// of the IOB time, the mean IOB over the time below zero, the lowest, and the time by clock hour (`clockAverage`'s,
    /// per day of IOB time).
    /// - Parameter days: a period's, oldest -> newest
    static func negativeIOB(_ days: [DayInsulin]) -> NegativeIOBSummary {
        let headline = days.filter(\.isHeadline)
        let iobSeconds = headline.reduce(0) { $0 + $1.iobSeconds }
        let negative = headline.reduce(0) { $0 + $1.negativeIOBSeconds }
        let area = headline.reduce(0) { $0 + $1.iob.negativeArea }
        let lowest = days.indices.filter { days[$0].isHeadline }
            .compactMap { index in days[index].iob.lowest.map { (iob: $0.iob, at: $0.at, day: index) } }
            .min { $0.iob < $1.iob }
        let duration = headline.reduce(0) { $0 + $1.day.duration }
        return NegativeIOBSummary(
            headlineDays: headline.count,
            secondsPerDay: iobSeconds > 0 ? negative / iobSeconds * .hours(24) : nil,
            share: iobSeconds > 0 ? negative / iobSeconds : nil,
            meanDepth: negative > 0 ? area / negative : nil,
            lowest: lowest?.iob,
            lowestAt: lowest?.at,
            lowestDay: lowest?.day,
            hours: clockAverage(days)?.negativeIOBSeconds?.within,
            iobCoverage: duration > 0 ? iobSeconds / duration : 0
        )
    }

    /// The IOB by time of day over the days: each 15-minute bin's 10th, 25th, 50th, 75th and 90th percentile of the
    /// days' means in it (`DayIOB.bins`), pooled with `pool` bins on either side (wrapping at midnight, as the AGP's);
    /// nil for a bin without a mean.
    /// - Parameter days: the IOB card's, the headline days
    static func iobProfile(_ days: [DayInsulin], pool: Int = 1) -> [IOBProfileBin?] {
        let count = DayIOB.binCount
        let pool = Swift.max(pool, 0)
        return (0 ..< count).map { bin -> IOBProfileBin? in
            let values = days.flatMap { day in
                (-pool ... pool).compactMap { offset -> Double? in
                    let index = ((bin + offset) % count + count) % count
                    return day.iob.bins.indices.contains(index) ? day.iob.bins[index] : nil
                }
            }.sorted()
            guard let p10 = quantile(values, 0.1),
                  let p25 = quantile(values, 0.25),
                  let p50 = quantile(values, 0.5),
                  let p75 = quantile(values, 0.75),
                  let p90 = quantile(values, 0.9)
            else { return nil }
            return IOBProfileBin(p10: p10, p25: p25, p50: p50, p75: p75, p90: p90)
        }
    }

    /// The `p` quantile (0...1) of sorted values, linear between the closest ranks; nil without values.
    static func quantile(_ sorted: [Double], _ p: Double) -> Double? {
        guard let first = sorted.first else { return nil }
        let rank = Swift.min(Swift.max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Swift.min(lower + 1, sorted.count - 1)
        guard lower > 0 || upper > 0 else { return first }
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
    }

    // MARK: - Timeline internals

    private struct SourcedIdentity: Hashable {
        let identity: PumpEventRecord.Identity
        let source: PumpEventSource
    }

    /// A clock hour of a day: `[start, end)`, the day's index and the local hour.
    private struct Slot {
        let interval: DateInterval
        let day: Int
        let hour: Int
    }

    /// A temp as counted: `[start, end)`, its rate and its amount spread over the span.
    private struct TempRun {
        let interval: DateInterval
        let rate: Double
        let amountPerSecond: Double
    }

    /// The schedule records, oldest -> newest, with their entries as (minute, U/h) by start.
    private struct Schedules {
        struct Entry {
            let minutes: Int
            let rate: Double
        }

        struct Record {
            let date: Date
            let entries: [Entry]

            /// The rate at a local minute of the day: the last entry starting at or before it (a schedule not
            /// starting at 00:00 wraps from the previous day's last entry).
            func rate(atMinute minute: Int) -> Double {
                var rate = entries.last?.rate ?? 0
                for entry in entries {
                    guard entry.minutes <= minute else { break }
                    rate = entry.rate
                }
                return rate
            }
        }

        let records: [Record]

        init(_ values: [BasalScheduleRecordValue]) {
            records = values
                .map { value in
                    Record(
                        date: value.date,
                        entries: value.entries
                            .sorted { $0.minutes < $1.minutes }
                            .map { Entry(minutes: $0.minutes, rate: Swift.max(Double($0.rate), 0)) }
                    )
                }
                .filter(\.entries.isNotEmpty)
                .sorted { $0.date < $1.date }
        }

        var isEmpty: Bool { records.isEmpty }
        var oldest: Date? { records.first?.date }

        /// The entries' minutes of the records in effect at some time of `interval`.
        func minutes(in interval: DateInterval) -> Set<Int> {
            var minutes = Set<Int>()
            for (index, record) in records.enumerated() {
                let next = index + 1 < records.count ? records[index + 1].date : .distantFuture
                // the oldest one stands for the time before it too
                let from = index == 0 ? Date.distantPast : record.date
                guard from < interval.end, interval.start < next else { continue }
                record.entries.forEach { minutes.insert($0.minutes) }
            }
            return minutes
        }
    }

    private static func timeline(
        usable events: [PumpEventRecord],
        coverage: [CoveredInterval],
        schedules: Schedules,
        days: [DateInterval],
        slots: [Slot],
        range: DateInterval,
        now: Date,
        timeZone: TimeZone
    ) -> [DeliverySegment] {
        let start = range.start
        let end = range.end
        guard end > start else { return [] }
        // nothing to fill with: nothing is covered
        let covered = schedules.isEmpty ? [] : coveredIntervals(coverage)
        let suspensionStarts = events.filter { $0.kind == .suspend }.map(\.date)
        let suspensions = suspensionIntervals(events, now: now)
        let temps = tempRuns(events, suspensionStarts: suspensionStarts, now: now)

        // every boundary inside the range
        var cuts: [Date] = [start, end]
        for interval in covered + suspensions {
            cuts.append(interval.start)
            cuts.append(interval.end)
        }
        for temp in temps {
            cuts.append(temp.interval.start)
            cuts.append(temp.interval.end)
        }
        cuts += schedules.records.map(\.date)
        for slot in slots {
            cuts.append(slot.interval.start)
            cuts.append(slot.interval.end)
        }
        for day in days where day.end > start && day.start < end {
            let clock = StatsClock.ClockDay(day, timeZone: timeZone)
            for minute in schedules.minutes(in: day) {
                cuts += clock.times(minute: minute)
            }
        }
        let sortedCuts = Array(Set(cuts.filter { $0 >= start && $0 <= end })).sorted()

        var segments: [DeliverySegment] = []
        segments.reserveCapacity(sortedCuts.count)
        var coveredIndex = 0
        var suspendedIndex = 0
        var tempIndex = 0
        var scheduleIndex = -1
        for index in sortedCuts.indices.dropLast() {
            let a = sortedCuts[index]
            let b = sortedCuts[index + 1]
            guard b > a else { continue }

            while coveredIndex < covered.count, covered[coveredIndex].end <= a { coveredIndex += 1 }
            while suspendedIndex < suspensions.count, suspensions[suspendedIndex].end <= a { suspendedIndex += 1 }
            while tempIndex < temps.count, temps[tempIndex].interval.end <= a { tempIndex += 1 }
            while scheduleIndex + 1 < schedules.records.count, schedules.records[scheduleIndex + 1].date <= a {
                scheduleIndex += 1
            }

            let isCovered = coveredIndex < covered.count && covered[coveredIndex].start <= a
            let isSuspended = suspendedIndex < suspensions.count && suspensions[suspendedIndex].start <= a
            let temp = tempIndex < temps.count && temps[tempIndex].interval.start <= a ? temps[tempIndex] : nil
            let duration = b.timeIntervalSince(a)

            var scheduledRate = 0.0
            var assumed = false
            if isCovered, schedules.records.isNotEmpty {
                let record = schedules.records[Swift.max(scheduleIndex, 0)]
                scheduledRate = record.rate(atMinute: StatsClock.minuteOfDay(a, in: timeZone))
                assumed = scheduleIndex < 0
            }

            let cause: DeliverySegment.Cause
            let rate: Double
            let amount: Double
            if isSuspended {
                cause = .suspended
                rate = 0
                amount = 0
            } else if let temp {
                cause = .temp
                rate = temp.rate
                amount = temp.amountPerSecond * duration
            } else if isCovered {
                cause = .scheduled
                rate = scheduledRate
                amount = scheduledRate * duration / .hours(1)
            } else {
                continue
            }
            segments.append(
                DeliverySegment(
                    interval: DateInterval(start: a, end: b),
                    cause: cause,
                    rate: rate,
                    amount: amount,
                    isCovered: isCovered,
                    scheduledRate: scheduledRate,
                    profileAssumed: assumed
                )
            )
        }
        return segments
    }

    /// The suspensions, merged, sorted; each from its suspend to the earliest of the next resume, the next pump
    /// delivery after it (a temp, or a bolus that isn't External Insulin: a pen says nothing about the pump) and `now`.
    /// A suspension runs on through coverage gaps (the app dead while the pump stays suspended): the time after the gap
    /// is still suspended, not filled with the schedule.
    /// - Parameter events: `usableEvents`' order
    private static func suspensionIntervals(_ events: [PumpEventRecord], now: Date) -> [DateInterval] {
        var intervals: [DateInterval] = []
        for (index, event) in events.enumerated() where event.kind == .suspend {
            guard event.date < now else { continue }
            var end = now
            for later in events[(index + 1)...] {
                if later.date >= end { break }
                let endsIt: Bool
                switch later.kind {
                case .resume:
                    endsIt = true
                case .tempBasal:
                    endsIt = later.date > event.date
                case .bolus:
                    endsIt = later.date > event.date && !later.isExternal && later.units > 0
                case .suspend:
                    endsIt = false
                }
                if endsIt {
                    end = later.date
                    break
                }
            }
            if end > event.date {
                intervals.append(DateInterval(start: event.date, end: end))
            }
        }
        return StatsIntervals.mergedDroppingEmpty(intervals)
    }

    /// The temps as counted, sorted, back to back at most: each from its start to the earliest of its nominal end, the
    /// next temp's start, a suspension starting in it (a suspension at its start leaves it nothing) and `now`.
    /// Amount: a final's delivered units in full, `units × kept / nominal` when a suspension clipped it; otherwise
    /// `rate × kept`.
    /// - Parameter events: `usableEvents`' order
    private static func tempRuns(_ events: [PumpEventRecord], suspensionStarts: [Date], now: Date) -> [TempRun] {
        let temps = events.filter { $0.kind == .tempBasal }
        var runs: [TempRun] = []
        for (index, temp) in temps.enumerated() {
            guard temp.date < now else { continue }
            let nominal = temp.nominalDuration
            var end = Swift.min(temp.date.addingTimeInterval(nominal), now)
            if let next = temps[(index + 1)...].first(where: { $0.date > temp.date }) {
                end = Swift.min(end, next.date)
            }
            var suspended = false
            if let suspension = suspensionStarts.first(where: { $0 >= temp.date && $0 < end }) {
                end = suspension
                suspended = true
            }
            let kept = end.timeIntervalSince(temp.date)
            guard kept > 0 else { continue }

            let amount: Double
            if let delivered = temp.deliveredUnits {
                amount = suspended ? (nominal > 0 ? delivered * Swift.min(kept / nominal, 1) : 0) : delivered
            } else {
                amount = Swift.max(temp.rate, 0) * kept / .hours(1)
            }
            runs.append(
                TempRun(
                    interval: DateInterval(start: temp.date, end: end),
                    rate: Swift.max(temp.rate, 0),
                    amountPerSecond: amount / kept
                )
            )
        }
        return runs
    }

    // MARK: - Day internals

    private struct DayBuilder {
        let day: DateInterval
        var hours = (0 ..< 24).map { HourInsulin(hour: $0) }
        var hasDeliveries = false
        var coveredUntil: Date?
        var profileAssumedBefore: Date?
        var boluses: [InsulinBolus] = []
        /// by quarter hour: Σ IOB × seconds, and the seconds
        var binSums = [Double](repeating: 0, count: DayIOB.binCount)
        var binSeconds = [Double](repeating: 0, count: DayIOB.binCount)
        var lowest: DayIOB.Lowest?
        var negativeArea = 0.0

        init(day: DateInterval) {
            self.day = day
        }

        mutating func add(_ segment: DeliverySegment, hour: Int, assumedBefore oldest: Date?) {
            hours[hour].add(segment)
            if segment.cause == .temp {
                hasDeliveries = true
            }
            if segment.isCovered {
                coveredUntil = Swift.max(coveredUntil ?? segment.interval.end, segment.interval.end)
            }
            if segment.profileAssumed, let oldest {
                profileAssumedBefore = oldest
            }
        }

        mutating func add(bolus: PumpEventRecord, hour: Int) {
            hasDeliveries = true
            boluses.append(InsulinBolus(
                date: bolus.date,
                units: bolus.units,
                isSMB: bolus.isSMB,
                isExternal: bolus.isExternal
            ))
            if bolus.isSMB {
                hours[hour].smb += bolus.units
            } else {
                hours[hour].bolus += bolus.units
            }
        }

        mutating func add(iobSeconds seconds: Double, negative: Bool, hour: Int) {
            hours[hour].iobSeconds += seconds
            if negative {
                hours[hour].negativeIOBSeconds += seconds
            }
        }

        /// A row's IOB over a piece of its span inside one clock hour's slot: to the hour's quarters, and below zero to
        /// the day's area and lowest.
        /// - Parameters:
        ///   - rowStart: the row's time (its lowest is at it)
        ///   - hourStart: the slot's start, the local hh:00 (or the day's start)
        mutating func add(iob: Double, over piece: DateInterval, rowStart: Date, hour: Int, hourStart: Date) {
            let quarter = TimeInterval.minutes(Double(DayIOB.binMinutes))
            var start = piece.start
            while start < piece.end {
                let index = Swift.min(Swift.max(Int(start.timeIntervalSince(hourStart) / quarter), 0), 3)
                var end = Swift.min(piece.end, hourStart.addingTimeInterval(quarter * Double(index + 1)))
                if end <= start {
                    end = piece.end
                }
                let bin = hour * 4 + index
                binSums[bin] += iob * end.timeIntervalSince(start)
                binSeconds[bin] += end.timeIntervalSince(start)
                start = end
            }

            guard iob < 0 else { return }
            negativeArea += iob * piece.duration
            // the first of equals
            if iob < lowest?.iob ?? 0 {
                lowest = DayIOB.Lowest(iob: iob, at: rowStart)
            }
        }

        func build(isToday: Bool) -> DayInsulin {
            func sum(_ value: (HourInsulin) -> Double) -> Double {
                hours.reduce(0) { $0 + value($1) }
            }
            return DayInsulin(
                day: day,
                isToday: isToday,
                basal: sum(\.basal),
                smb: sum(\.smb),
                bolus: sum(\.bolus),
                scheduled: sum(\.scheduled),
                zeroBasalSeconds: sum(\.zeroBasalSeconds),
                coveredSeconds: sum(\.coveredSeconds),
                negativeIOBSeconds: sum(\.negativeIOBSeconds),
                iobSeconds: sum(\.iobSeconds),
                iob: DayIOB(
                    bins: zip(binSums, binSeconds).map { sum, seconds in seconds > 0 ? sum / seconds : nil },
                    lowest: lowest,
                    negativeArea: negativeArea
                ),
                hours: hours,
                hasDeliveries: hasDeliveries,
                coveredUntil: coveredUntil,
                profileAssumedBefore: profileAssumedBefore,
                // a past day is cached: its SMBs (dozens a day) are in its hours only; in `usableEvents`' order (by date)
                boluses: isToday ? boluses : boluses.filter { !$0.isSMB }
            )
        }
    }

    /// The clock hours of the days, oldest -> newest: each day cut at the local times hh:00 (both passes of a repeated
    /// one; a skipped one has none), each piece the hour its local clock shows at its start.
    private static func hourSlots(_ days: [DateInterval], timeZone: TimeZone) -> [Slot] {
        var slots: [Slot] = []
        for (index, day) in days.enumerated() where day.duration > 0 {
            var cuts: [Date] = [day.start, day.end]
            let clock = StatsClock.ClockDay(day, timeZone: timeZone)
            for hour in 0 ..< 24 {
                cuts += clock.times(minute: hour * 60)
            }
            let sorted = Array(Set(cuts)).sorted()
            for cut in sorted.indices.dropLast() where sorted[cut + 1] > sorted[cut] {
                let start = sorted[cut]
                slots.append(
                    Slot(
                        interval: DateInterval(start: start, end: sorted[cut + 1]),
                        day: index,
                        hour: StatsClock.minuteOfDay(start, in: timeZone) / 60
                    )
                )
            }
        }
        return slots
    }

    private static func slot(containing date: Date, in slots: [Slot]) -> Slot? {
        let index = firstSlot(endingAfter: date, in: slots)
        guard index < slots.count, slots[index].interval.start <= date else { return nil }
        return slots[index]
    }

    /// The first slot ending after the date (a binary search: the slots are sorted and don't overlap).
    private static func firstSlot(endingAfter date: Date, in slots: [Slot]) -> Int {
        slots.partitionIndex { $0.interval.end > date }
    }
}
