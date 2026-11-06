import Foundation

/// The loop numbers of a range (the Home Loops card's, the last 24 h, `Home.loopsRange`; the Statistics Loop tab's) and
/// of each calendar day (the Loops screen's, `LoopHistory`), as pure functions: no Core Data, no `Date()`, no global
/// calendar. `HomeLoopsStore` reads the inputs and makes them off the main actor (from cached days where it can).
///
/// A loop is counted per slot, not per attempt:
/// - Slots: the CGM readings a loop can run on (`expectedReadings`, thinned from each day's newest reading on; all of
///   them with the 1-minute loop). A slot runs from its reading to the next one; a day's last one into the next day, up
///   to its first reading a loop could run on after it (`slotsEnd`; `Config.slotLookahead` at most: the loop of a
///   reading just before midnight starts after it), the window's last one up to its end (the read's now). A CGM gap
///   makes no slots.
/// - A slot is a success when a loop with the status "Success" started in it; failed when only failed loops did, its
///   cause the last one's (`LoopFailureCause`); missed when no loop started in it ("No loop ran").
/// - The share: successes ÷ slots; over several days pooled (Σ successes ÷ Σ slots).
/// - The card's counts are plain, not per slot: the "Success" records started in the window (`successfulLoops`) and the
///   CGM readings in it, exact duplicates once, not thinned (`readings`).
///
/// Everything is summed from the window's calendar days (`Day`, midnight to midnight: `GlucoseStatsEngine.window`), and
/// a day's numbers depend on that day's records and readings, and the next day's first `Config.slotLookahead`, only:
/// a day `Config.settleTime` past its end is cached as it is.
/// - Gaps: between consecutive loop starts (any status), by the `GapDetection` rule (over 1.5 of the loop's cadence),
///   whatever the cause (a CGM outage too): within each day (the cadence learnt from that day's starts), and across the
///   day boundaries (between a day's last start and the next day's first one, at the 5-minute cadence), from the start
///   before the window on. The ongoing gap, from the newest start to the read's now (the window's end), counts once it is
///   `Config.longGap` long: the result is as of its read, nothing moves it on with the time alone. A gap of
///   `Config.longGap` or more carries the slots inside it (`CountedGap`): few, the CGM was out; most, no loop ran.
/// - The strip (Today and 24 h): a column per half hour of the clock, its height the bucket's successes ÷ its slots; the
///   gaps of `Config.longGap` or more marked at their time.
struct HomeLoopStats: Sendable, Equatable {
    enum Config {
        /// gaps this long or longer are marked on the strip; an ongoing one counts from it (the header's loop ring
        /// covers the shorter misses)
        static let longGap: TimeInterval = .minutes(15)
        /// the status of a loop that ran (`APSManager`)
        static let success = "Success"
        /// a day's slots are kept for these equal parts of it (half hours on a day of 24 hours): the Loops screen's strip
        static let dayParts = 48
        /// the strip's buckets: half hours of the clock
        static let bucketLength: TimeInterval = .minutes(30)
        /// how far into the next day a day's last slot reaches at most: up to the next day's first reading
        static let slotLookahead: TimeInterval = .minutes(15)
        /// a complete day is cached once this long past its end: its last slot's loops (`slotLookahead`) are saved then
        static let settleTime: TimeInterval = .minutes(20)
        /// a gap's readings are those its due loops could have run on: up to this long before the start that ends it (the
        /// reading that start ran on is the gap's end)
        static let readingLead: TimeInterval = .minutes(1)
    }

    /// A loop record: when it started, whether it is a "Success", why not, and how long it ran.
    struct Record: Sendable, Equatable {
        let start: Date
        let success: Bool
        /// why it failed; nil for a success
        let cause: LoopFailureCause?
        /// seconds; nil when not known
        let duration: TimeInterval?

        init(start: Date, success: Bool, cause: LoopFailureCause? = nil, duration: TimeInterval? = nil) {
            self.start = start
            self.success = success
            self.cause = success ? nil : cause ?? LoopFailureCause.of(error: nil, status: nil)
            self.duration = duration
        }

        /// A stored record: the status "Success" ran; any other failed, why from its error (or its status, which holds
        /// the error too), grouped by `cause` (a memo of it in the app, `LoopFailureCause.Memo`). `durationMinutes` as
        /// stored (`LoopStatRecord.duration`).
        init(
            start: Date,
            status: String?,
            error: String?,
            durationMinutes: Double?,
            cause: (_ error: String?, _ status: String?) -> LoopFailureCause = LoopFailureCause.of
        ) {
            let success = status == Config.success
            self.init(
                start: start,
                success: success,
                cause: success ? nil : cause(error, status),
                duration: durationMinutes.map { $0 * 60 }
            )
        }
    }

    /// What became of a slot.
    enum Outcome: Sendable, Equatable {
        case success
        /// the last failed attempt's cause
        case failed(LoopFailureCause)
        /// no loop started in it
        case missed
    }

    /// A slot: its reading and what became of it.
    struct Slot: Sendable, Equatable {
        let start: Date
        let outcome: Outcome
    }

    /// Slots counted.
    struct Slots: Sendable, Equatable {
        var count = 0
        var successes = 0
        var failed = 0
        var missed = 0

        init(count: Int = 0, successes: Int = 0, failed: Int = 0, missed: Int = 0) {
            self.count = count
            self.successes = successes
            self.failed = failed
            self.missed = missed
        }

        init(_ slots: [Slot]) {
            self.init()
            for slot in slots {
                add(slot.outcome)
            }
        }

        mutating func add(_ outcome: Outcome) {
            count += 1
            switch outcome {
            case .success: successes += 1
            case .failed: failed += 1
            case .missed: missed += 1
            }
        }

        static func + (lhs: Slots, rhs: Slots) -> Slots {
            Slots(
                count: lhs.count + rhs.count,
                successes: lhs.successes + rhs.successes,
                failed: lhs.failed + rhs.failed,
                missed: lhs.missed + rhs.missed
            )
        }

        /// successes ÷ slots in percent (a slot succeeds once at most); nil without slots
        var percent: Double? {
            count > 0 ? Double(successes) / Double(count) * 100 : nil
        }
    }

    /// A column of the strip.
    struct Bucket: Sendable, Equatable {
        let interval: DateInterval
        /// the slots inside that succeeded
        let successes: Int
        /// the slots starting inside
        let slots: Int

        /// successes ÷ slots; nil without slots (no column)
        var fraction: Double? {
            slots > 0 ? Double(successes) / Double(slots) : nil
        }
    }

    /// A gap of `Config.longGap` or more, with the slots inside it (the readings its due loops could have run on).
    struct CountedGap: Sendable, Equatable {
        let gap: LoopGap
        let slots: Int

        /// Fewer readings than half the loops it missed: the CGM was out (or the phone got none); otherwise no loop ran
        /// on the readings there were.
        var lacksReadings: Bool {
            slots * 2 <= gap.skippedLoops
        }
    }

    /// One calendar day of the window (the part of it inside), summed; what the card, the Loop tab and the Loops screen
    /// need of it. Depends on the day's records and readings (and the next day's first `Config.slotLookahead`) only, so a
    /// complete day is cached as it is (`HomeLoopsStore`).
    struct Day: Sendable, Equatable {
        /// the whole calendar day
        let day: DateInterval
        /// the part of it in the window
        let interval: DateInterval
        /// the records started in the part, whatever their slot: what the store's count check compares
        let records: Int
        /// the "Success" records of those (every loop that ran, whatever its slot: the card's "loops")
        let successfulLoops: Int
        /// the CGM readings in the part as read (`HomeLoopsSource.readingTimes`: `glucose > 0`, before any thinning),
        /// exact duplicates once (the concurrent Nightscout-import saves): the card's "readings"
        let readings: Int
        /// where the last slot ends after the part (`slotsEnd`; the part's end without one), and the records started from
        /// the part's end up to there: the last slot's in the next day, which the store's count check compares too
        let lookaheadEnd: Date
        let lookaheadRecords: Int
        let slots: Slots
        /// the failed slots by their cause
        let causes: [LoopFailureCause: Int]
        /// the durations of the loops started in the slots, in tenths of a second, counted
        let durations: [Int: Int]
        /// the slots, and those that succeeded, in each of the day's `Config.dayParts` equal parts (by their reading)
        let partSlots: [Int]
        let partSuccesses: [Int]
        let firstStart: Date?
        let lastStart: Date?
        /// the longest gap between the day's starts, and those of `Config.longGap` or more, oldest -> newest
        let longestGap: LoopGap?
        let longGaps: [CountedGap]
        /// the slots before the first start (up to `Config.readingLead` before it) and from the last one on: the gaps
        /// across the day's edges count them
        let slotsBeforeFirstStart: Int
        let slotsAfterLastStart: Int
    }

    /// The gaps of the days.
    struct Gaps: Sendable, Equatable {
        /// the longest gap between two loop starts (not the ongoing one); nil without
        let longestClosed: LoopGap?
        /// the gaps of `Config.longGap` or more between two loop starts, oldest -> newest
        let marked: [CountedGap]
        /// from the newest start to the end, once it is `Config.longGap` long
        let ongoing: CountedGap?
        /// the newest loop start, also before the days; nil without one
        let newestStart: Date?
    }

    let period: StatsPeriod
    /// `[start, now]`: Today and the N-day ranges from midnight (the stats bar's window), 24 h the 24 hours before now
    let window: DateInterval
    /// the window's slots
    let slots: Slots
    /// all records started in the window
    let records: Int
    /// the "Success" records started in the window: the loops that ran, each counted (not per slot)
    let successfulLoops: Int
    /// the CGM readings in the window, exact duplicates once, not thinned (`Day.readings`)
    let readings: Int
    /// the start of today (the day of the window's end): the 24 h card marks it
    let todayStart: Date
    /// the slots of today's part of the window: the 24 h card's "Today"
    let todaySlots: Slots
    /// Today and 24 h only (none for the N-day ranges), oldest -> newest, the last one ending at now
    let buckets: [Bucket]
    /// the longest gap between two loop starts (not the ongoing one); nil without
    let longestClosedGap: LoopGap?
    /// the gaps of `Config.longGap` or more between two loop starts, oldest -> newest
    let closedMarkedGaps: [LoopGap]
    /// the gap from the newest start (also before the window) to the window's end, the read's now, once it is
    /// `Config.longGap` long
    let ongoingGap: LoopGap?
    /// the newest loop start, also before the window; nil without one
    let newestStart: Date?

    /// no loop record in the window
    var isEmpty: Bool { records == 0 }

    /// successes ÷ slots in percent; nil without slots
    var percent: Double? { slots.percent }

    /// the longest gap, the ongoing one included (when longer, not as long); nil without gaps
    var longestGap: LoopGap? {
        guard let ongoingGap else { return longestClosedGap }
        guard let closed = longestClosedGap, ongoingGap.duration <= closed.duration else { return ongoingGap }
        return closed
    }

    /// the gaps of `Config.longGap` or more, the ongoing one last; oldest -> newest
    var markedGaps: [LoopGap] {
        closedMarkedGaps + (ongoingGap.map { [$0] } ?? [])
    }
}

extension HomeLoopStats {
    /// The N-day ranges are summed from the days (cached ones too, `HomeLoopsStore`), without a strip; Today and 24 h are
    /// made from the raw records and readings (a day at most), with it.
    static func readsDays(_ period: StatsPeriod) -> Bool {
        switch period {
        case .last24h,
             .today: return false
        case .days7,
             .days14,
             .days30,
             .days90,
             .weeks4,
             .weeks5,
             .weeks8,
             .weeks13: return true
        }
    }

    /// The numbers from the raw records and readings: every day computed (`HomeLoopsStore` uses cached days for the
    /// complete ones of the N-day ranges, with the same result).
    /// - Parameters:
    ///   - records: the loop records started in the window (more are ignored), any order
    ///   - previousStart: the newest loop start before the window's start, nil when there is none
    ///   - readings: the CGM readings' times in the window (more are ignored), any order
    static func make(
        period: StatsPeriod,
        records: [Record],
        previousStart: Date?,
        readings: [Date],
        allowOneMinuteLoop: Bool,
        now: Date,
        calendar: Calendar
    ) -> HomeLoopStats {
        let window = GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar)
        // sorted once, each day a slice
        let records = Array(slice(records.sorted { $0.start < $1.start }, by: \.start, in: window, throughEnd: true))
        let readings = Array(slice(readings.sorted(), by: { $0 }, in: window, throughEnd: false))
        let segments = self.segments(of: window, calendar: calendar)
        let days = self.days(
            segments,
            windowEnd: window.end,
            records: records,
            readings: readings,
            allowOneMinuteLoop: allowOneMinuteLoop
        )
        let buckets: [Bucket]
        if readsDays(period) {
            buckets = []
        } else {
            let slots = segments.flatMap { segment in
                self.slots(
                    segment.interval,
                    windowEnd: window.end,
                    records: records,
                    readings: readings,
                    allowOneMinuteLoop: allowOneMinuteLoop
                )
            }
            buckets = self.buckets(slots, intervals: bucketIntervals(of: window, calendar: calendar))
        }
        return assemble(
            period: period,
            window: window,
            days: days,
            buckets: buckets,
            previousStart: previousStart,
            calendar: calendar
        )
    }

    /// The window's calendar days, whole and as the part inside the window, oldest -> newest.
    static func segments(of window: DateInterval, calendar: Calendar) -> [(day: DateInterval, interval: DateInterval)] {
        StatsClock.calendarDays(in: window, calendar: calendar).map { day in
            (day, DateInterval(start: max(day.start, window.start), end: max(min(day.end, window.end), window.start)))
        }
    }

    /// The elements of a sorted array (oldest -> newest) in `[start, end)`, or `[start, end]` with `throughEnd`: found by
    /// binary search.
    static func slice<Element>(
        _ sorted: [Element],
        by date: (Element) -> Date,
        in interval: DateInterval,
        throughEnd: Bool
    ) -> ArraySlice<Element> {
        let lower = firstIndex(in: sorted, by: date) { interval.start <= $0 }
        let upper = firstIndex(in: sorted, by: date) { throughEnd ? interval.end < $0 : interval.end <= $0 }
        return sorted[lower ..< max(lower, upper)]
    }

    /// The first index whose date satisfies `isAtOrAfter` (false up to some index, true from there on); `count` if none.
    private static func firstIndex<Element>(
        in sorted: [Element],
        by date: (Element) -> Date,
        where isAtOrAfter: (Date) -> Bool
    ) -> Int {
        sorted.partitionIndex { isAtOrAfter(date($0)) }
    }

    /// `[start, end)`, or `[start, end]` for the window's last part (a loop at now)
    static func contains(_ interval: DateInterval, _ date: Date, throughEnd: Bool) -> Bool {
        guard interval.start <= date else { return false }
        return throughEnd ? date <= interval.end : date < interval.end
    }

    // MARK: - Slots

    /// Where a part's last slot ends: the window's end for its last part; otherwise the next day's first reading a loop
    /// could run on after the slot's, `Config.slotLookahead` after the part at most, and the window's end at most. With
    /// the 5-minute loop that is a reading `FrequentGlucoseFiltering.fiveMinuteInterval` or more after the slot's, as
    /// inside a day: each day is thinned on its own (`expectedReadings`), so the next day's first readings can be
    /// seconds after it (1-minute readings; a 5-minute sensor's jitter), and the loop (its throttle) skips them. Cut
    /// there, the slot would miss the loop that ran for it. The records between this end and the next day's first slot
    /// count for neither day; a loop between that slot's reading and this end counts for both (the restart at midnight
    /// can put the two slots a minute apart: the one loop is due for both). The next day's slots don't depend on this
    /// day: complete days are cached on their own.
    /// - Parameters:
    ///   - lastSlotStart: the reading of the part's last slot; nil without slots
    ///   - readings: sorted, oldest -> newest, covering the lookahead
    static func slotsEnd(
        of interval: DateInterval,
        windowEnd: Date,
        lastSlotStart: Date?,
        readings: [Date],
        allowOneMinuteLoop: Bool
    ) -> Date {
        guard interval.end < windowEnd else { return windowEnd }
        let cap = min(interval.end.addingTimeInterval(Config.slotLookahead), windowEnd)
        var from = interval.end
        if !allowOneMinuteLoop, let lastSlotStart {
            from = max(from, lastSlotStart.addingTimeInterval(FrequentGlucoseFiltering.fiveMinuteInterval))
        }
        guard from < cap else { return cap }
        return slice(readings, by: { $0 }, in: DateInterval(start: from, end: cap), throughEnd: false).first ?? cap
    }

    /// What became of each slot: a slot is `[its reading, the next one)`, the last one up to `end` (`[.., end]` with
    /// `throughEnd`, a loop at now); the records before the first reading belong to the slot before (the day before's).
    ///
    /// Each slot counts once, whatever its attempts: after a failed loop `APSManager.loop` doesn't hold the next one
    /// back (its throttle applies only after a completed loop, `lastLoopDate > lastStartLoopDate`), so a failing loop is
    /// tried again on every trigger, several times a slot, while a working one runs once. Counted per attempt, failures
    /// would weigh several times over and the share would depend on how often it was retried.
    /// - Parameters:
    ///   - starts: the slots' readings, oldest -> newest
    ///   - records: sorted by their start, oldest -> newest
    static func outcomes(starts: [Date], end: Date, throughEnd: Bool, records: [Record]) -> [Slot] {
        var slots: [Slot] = []
        slots.reserveCapacity(starts.count)
        let firstStart = starts.first
        var index = firstIndex(in: records, by: \.start) { date in firstStart.map { $0 <= date } ?? true }
        for (position, start) in starts.enumerated() {
            let isLast = position == starts.count - 1
            let slotEnd = isLast ? end : starts[position + 1]
            var succeeded = false
            var lastFailure: LoopFailureCause?
            while index < records.count {
                let record = records[index]
                let inside = isLast && throughEnd ? record.start <= slotEnd : record.start < slotEnd
                guard inside else { break }
                if record.success {
                    succeeded = true
                } else if let cause = record.cause {
                    lastFailure = cause
                }
                index += 1
            }
            let outcome: Outcome = succeeded ? .success : lastFailure.map { .failed($0) } ?? .missed
            slots.append(Slot(start: start, outcome: outcome))
        }
        return slots
    }

    /// The slots of a part of the window: its readings thinned, oldest -> newest, the last one up to `slotsEnd`.
    /// - Parameters:
    ///   - records: sorted, covering the part and its lookahead (more are ignored)
    ///   - readings: sorted, covering the part and its lookahead (more are ignored)
    static func slots(
        _ interval: DateInterval,
        windowEnd: Date,
        records: [Record],
        readings: [Date],
        allowOneMinuteLoop: Bool
    ) -> [Slot] {
        slotsAndEnd(
            interval,
            windowEnd: windowEnd,
            records: records,
            readings: readings,
            allowOneMinuteLoop: allowOneMinuteLoop
        ).slots
    }

    /// `slots`, and where the last one ends (`slotsEnd`).
    private static func slotsAndEnd(
        _ interval: DateInterval,
        windowEnd: Date,
        records: [Record],
        readings: [Date],
        allowOneMinuteLoop: Bool
    ) -> (slots: [Slot], end: Date) {
        let isLast = interval.end == windowEnd
        let starts = Array(expectedReadings(
            Array(slice(readings, by: { $0 }, in: interval, throughEnd: false)),
            allowOneMinuteLoop: allowOneMinuteLoop
        ).reversed())
        let end = slotsEnd(
            of: interval,
            windowEnd: windowEnd,
            lastSlotStart: starts.last,
            readings: readings,
            allowOneMinuteLoop: allowOneMinuteLoop
        )
        let records = Array(slice(records, by: \.start, in: DateInterval(start: interval.start, end: end), throughEnd: isLast))
        return (outcomes(starts: starts, end: end, throughEnd: isLast, records: records), end)
    }

    // MARK: - Days

    /// The days of the segments (`segments`), oldest -> newest.
    /// - Parameters:
    ///   - windowEnd: the window's end: its last part's slots end there, the others' at most `Config.slotLookahead`
    ///     after them
    ///   - records: sorted, covering the segments and the lookahead after the last one
    ///   - readings: sorted, covering the segments and the lookahead after the last one
    static func days(
        _ segments: some Collection<(day: DateInterval, interval: DateInterval)>,
        windowEnd: Date,
        records: [Record],
        readings: [Date],
        allowOneMinuteLoop: Bool
    ) -> [Day] {
        segments.map { segment in
            day(
                segment.day,
                interval: segment.interval,
                windowEnd: windowEnd,
                records: records,
                readings: readings,
                allowOneMinuteLoop: allowOneMinuteLoop
            )
        }
    }

    /// One day's numbers.
    /// - Parameters:
    ///   - day: the whole calendar day
    ///   - interval: its part in the window
    ///   - records: sorted, covering the part and its lookahead (more are ignored)
    ///   - readings: sorted, covering the part and its lookahead (more are ignored)
    static func day(
        _ day: DateInterval,
        interval: DateInterval,
        windowEnd: Date,
        records: [Record],
        readings: [Date],
        allowOneMinuteLoop: Bool
    ) -> Day {
        let (slots, end) = slotsAndEnd(
            interval,
            windowEnd: windowEnd,
            records: records,
            readings: readings,
            allowOneMinuteLoop: allowOneMinuteLoop
        )
        let isLast = interval.end == windowEnd
        let own = slice(records, by: \.start, in: interval, throughEnd: isLast)
        // the last slot's part in the next day (none without slots, or for the window's last part)
        let lookaheadEnd = slots.isEmpty ? interval.end : max(interval.end, end)
        let lookaheadRecords = slice(
            records,
            by: \.start,
            in: DateInterval(start: interval.end, end: lookaheadEnd),
            throughEnd: false
        ).count
        let starts = own.map(\.start)

        var causes: [LoopFailureCause: Int] = [:]
        var partSlots = Array(repeating: 0, count: Config.dayParts)
        var partSuccesses = Array(repeating: 0, count: Config.dayParts)
        for slot in slots {
            let part = dayPart(of: slot.start, in: day)
            partSlots[part] += 1
            switch slot.outcome {
            case .success:
                partSuccesses[part] += 1
            case let .failed(cause):
                causes[cause, default: 0] += 1
            case .missed: break
            }
        }

        // the loops of the slots: from the first slot's reading to the last one's end
        var durations: [Int: Int] = [:]
        if let first = slots.first {
            for record in slice(records, by: \.start, in: DateInterval(start: first.start, end: end), throughEnd: isLast) {
                guard let duration = record.duration, duration >= 0 else { continue }
                durations[Int((duration * 10).rounded()), default: 0] += 1
            }
        }

        let slotStarts = slots.map(\.start)
        let slotsIn = { (range: DateInterval) in slice(slotStarts, by: { $0 }, in: range, throughEnd: false).count }
        let before = { (date: Date) in date.addingTimeInterval(-Config.readingLead) }
        // within the day: no ongoing gap (its last start is the end)
        let gaps = LoopGap.detect(in: starts, allowOneMinuteLoop: allowOneMinuteLoop, now: starts.last ?? day.start)
        let longGaps = gaps.filter { $0.duration >= Config.longGap }.map { gap in
            CountedGap(gap: gap, slots: slotsIn(DateInterval(start: gap.start, end: max(gap.start, before(gap.end)))))
        }

        return Day(
            day: day,
            interval: interval,
            records: own.count,
            successfulLoops: own.reduce(0) { $1.success ? $0 + 1 : $0 },
            readings: Set(slice(readings, by: { $0 }, in: interval, throughEnd: false)).count,
            lookaheadEnd: lookaheadEnd,
            lookaheadRecords: lookaheadRecords,
            slots: Slots(slots),
            causes: causes,
            durations: durations,
            partSlots: partSlots,
            partSuccesses: partSuccesses,
            firstStart: starts.first,
            lastStart: starts.last,
            longestGap: longest(gaps),
            longGaps: longGaps,
            slotsBeforeFirstStart: starts.first.map { first in
                slotsIn(DateInterval(start: interval.start, end: max(interval.start, before(first))))
            } ?? slots.count,
            slotsAfterLastStart: starts.last.map { last in
                slotsIn(DateInterval(start: last, end: max(last, interval.end)))
            } ?? slots.count
        )
    }

    /// The day's equal part a time falls in (`Config.dayParts` of them).
    static func dayPart(of date: Date, in day: DateInterval) -> Int {
        guard day.duration > 0 else { return 0 }
        let part = Int((date.timeIntervalSince(day.start) / day.duration * Double(Config.dayParts)).rounded(.down))
        return min(max(part, 0), Config.dayParts - 1)
    }

    /// The card's numbers from the window's days, oldest -> newest (`segments`), and its buckets.
    static func assemble(
        period: StatsPeriod,
        window: DateInterval,
        days: [Day],
        buckets: [Bucket],
        previousStart: Date?,
        calendar: Calendar
    ) -> HomeLoopStats {
        let gaps = self.gaps(of: days, previousStart: previousStart, end: window.end)
        let todayStart = calendar.startOfDay(for: window.end)
        return HomeLoopStats(
            period: period,
            window: window,
            slots: days.reduce(Slots()) { $0 + $1.slots },
            records: days.reduce(0) { $0 + $1.records },
            successfulLoops: days.reduce(0) { $0 + $1.successfulLoops },
            readings: days.reduce(0) { $0 + $1.readings },
            todayStart: todayStart,
            todaySlots: days.last { $0.day.start == todayStart }?.slots ?? Slots(),
            buckets: buckets,
            longestClosedGap: gaps.longestClosed,
            closedMarkedGaps: gaps.marked.map(\.gap),
            ongoingGap: gaps.ongoing?.gap,
            newestStart: gaps.newestStart
        )
    }

    /// The gaps of the days, oldest -> newest (`segments`): each day's, and those across the days' edges (or from the
    /// start before the first day), and the ongoing one up to `end` (the read's now).
    static func gaps(of days: [Day], previousStart: Date?, end: Date) -> Gaps {
        var longestGap: LoopGap?
        var marked: [CountedGap] = []
        let longer = { (gap: LoopGap) in
            longestGap.map { $0.duration < gap.duration } ?? true
        }

        var previous = previousStart
        // the slots since the previous start (none known before the days)
        var pending = 0
        for day in days {
            guard let first = day.firstStart, let last = day.lastStart else {
                pending += day.slots.count
                continue
            }
            // across the day boundary (or from the start before the days): the 5-minute cadence
            if let previous, let join = LoopGap.detect(in: [previous, first], allowOneMinuteLoop: false, now: first).first {
                if join.duration >= Config.longGap {
                    marked.append(CountedGap(gap: join, slots: pending + day.slotsBeforeFirstStart))
                }
                if longer(join) {
                    longestGap = join
                }
            }
            if let gap = day.longestGap, longer(gap) {
                longestGap = gap
            }
            marked += day.longGaps
            previous = last
            pending = day.slotsAfterLastStart
        }

        // the ongoing gap up to now: as of this read
        var ongoing: CountedGap?
        if let previous, end.timeIntervalSince(previous) >= Config.longGap {
            ongoing = CountedGap(
                gap: LoopGap(start: previous, end: end, loopInterval: GapDetection.Config.defaultLoopInterval, ongoing: true),
                slots: pending
            )
        }
        return Gaps(longestClosed: longestGap, marked: marked, ongoing: ongoing, newestStart: previous)
    }

    /// The readings a loop can run on, newest -> oldest, exact duplicates (the concurrent Nightscout-import saves) once:
    /// all of them with the 1-minute loop, otherwise the ones oref gets, at least 4.5 min apart from the newest one on
    /// (`FrequentGlucoseFiltering`, the old card's `glucoseFrequencyFiltered`). Applied to each day on its own, so a day
    /// doesn't depend on the next one (oref's walk over several days can differ by a reading at a midnight).
    static func expectedReadings(_ dates: [Date], allowOneMinuteLoop: Bool) -> [Date] {
        let sorted = Set(dates).sorted(by: >)
        guard !allowOneMinuteLoop, var kept = sorted.first else { return sorted }
        var result = [kept]
        for date in sorted.dropFirst() where kept.timeIntervalSince(date) >= FrequentGlucoseFiltering.fiveMinuteInterval {
            result.append(date)
            kept = date
        }
        return result
    }

    /// The median of durations counted in tenths of a second (`Day.durations`), in seconds: the lower one of an even
    /// count; nil without any.
    static func medianDuration(_ durations: [Int: Int]) -> TimeInterval? {
        let total = durations.values.reduce(0, +)
        guard total > 0 else { return nil }
        let target = (total - 1) / 2
        var seen = 0
        for (tenths, count) in durations.sorted(by: { $0.key < $1.key }) {
            seen += count
            if seen > target {
                return Double(tenths) / 10
            }
        }
        return nil
    }

    // MARK: - Buckets

    /// The strip's buckets, oldest -> newest: each calendar day's half hours of the clock (46 or 50 on a 23- or 25-hour
    /// day), cut to the window (the first one at its start, the last one at its end, now): midnight is an edge.
    static func bucketIntervals(of window: DateInterval, calendar: Calendar) -> [DateInterval] {
        guard window.duration > 0 else { return [] }
        return StatsClock.calendarDays(in: window, calendar: calendar).flatMap { day in
            let count = max(1, Int((day.duration / Config.bucketLength).rounded()))
            let step = day.duration / Double(count)
            var buckets: [DateInterval] = []
            for index in 0 ..< count {
                let bucketStart = day.start.addingTimeInterval(step * Double(index))
                let bucketEnd = index == count - 1 ? day.end : day.start.addingTimeInterval(step * Double(index + 1))
                // before the window (24 h), after it (now)
                guard bucketEnd > window.start else { continue }
                guard bucketStart < window.end else { break }
                buckets.append(DateInterval(start: max(bucketStart, window.start), end: min(bucketEnd, window.end)))
            }
            return buckets
        }
    }

    /// The slots in each bucket, by their reading, and those that succeeded.
    /// - Parameter slots: oldest -> newest
    static func buckets(_ slots: [Slot], intervals: [DateInterval]) -> [Bucket] {
        var successes = Array(repeating: 0, count: intervals.count)
        var counts = Array(repeating: 0, count: intervals.count)
        var index = 0
        for slot in slots {
            while index + 1 < intervals.count, intervals[index].end <= slot.start {
                index += 1
            }
            guard index < intervals.count, intervals[index].start <= slot.start else { continue }
            counts[index] += 1
            if slot.outcome == .success {
                successes[index] += 1
            }
        }
        return intervals.indices.map { Bucket(interval: intervals[$0], successes: successes[$0], slots: counts[$0]) }
    }

    /// the longest, the earliest of equal ones
    private static func longest(_ gaps: [LoopGap]) -> LoopGap? {
        var result: LoopGap?
        for gap in gaps where result.map({ $0.duration < gap.duration }) ?? true {
            result = gap
        }
        return result
    }
}
