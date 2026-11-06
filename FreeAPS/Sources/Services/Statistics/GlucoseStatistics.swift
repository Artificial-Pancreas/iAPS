import Foundation
import UIKit

private typealias Engine = GlucoseStatsEngine

/// Where the statistics read the readings from: `CoreDataStorage`, a fake in the tests.
protocol GlucosePointSource: Sendable {
    /// The readings the statistics count, `[from, to)`, oldest -> newest. Throws when they (or any part of them)
    /// couldn't be read: the statistics never cache or hold what a failed read gave.
    func fetchGlucosePoints(from: Date, to: Date) async throws -> [GlucosePoint]
    /// The oldest `limit` of them, in one small fetch (is there a reading before a date?). Throws as the other.
    func fetchGlucosePoints(from: Date, to: Date, limit: Int) async throws -> [GlucosePoint]
}

extension GlucosePointSource {
    /// The whole range, cut to `limit` (a source without a fetch limit of its own: the tests' fakes).
    func fetchGlucosePoints(from: Date, to: Date, limit: Int) async throws -> [GlucosePoint] {
        Array(try await fetchGlucosePoints(from: from, to: to).prefix(Swift.max(limit, 0)))
    }
}

/// What the Trace shows: one calendar day, or the 24 hours.
enum TraceRange: Sendable, Hashable {
    /// the 24 hours before E
    case last24h
    /// the calendar day of the date, up to E
    case day(Date)
}

struct TraceData: Sendable, Equatable {
    /// the x axis: the whole calendar day, or the 24 hours before E
    let domain: DateInterval
    /// `[start, E)`: the day up to E (empty for a day after it), or the 24 hours
    let window: DateInterval
    /// the readings starting inside the window, oldest -> newest
    let points: [WeightedPoint]
    let summary: GlucoseSummary
}

/// The days of a period (Daily), with the window they make up and the rule that gave its end.
struct PeriodDays: Sendable, Equatable {
    /// `[start, E)`
    let window: DateInterval
    let endRule: StatsEndRule
    /// `GlucoseStatsEngine.days(for: period, ...)`'s, oldest -> newest
    let days: [DayAggregate]
}

/// The glucose statistics of Home, Statistics and the stats upload: reads the readings and runs the engine off the
/// main thread, with a per-day aggregate cache of the complete days.
///
/// The actor only holds the cache and the held readings; the computation runs in static (so nonisolated) async
/// helpers on value snapshots, so a 90-day AGP doesn't hold up a Home refresh.
///
/// Staleness: every invalidation bumps `generation`. Readings are read with the generation they reflect (`asOf`), and
/// a day computed from them is stored only when the day wasn't invalidated after that: a day invalidated while it was
/// being computed is returned, but not stored. A read that failed reflects no generation: nothing computed from it is
/// stored (the request still gets a result, without those readings).
///
/// Consumers (Home, Statistics, the stats upload):
/// - Refresh on `appCoordinator.glucoseStatsChanged` only, never on `glucoseSmoothed`: that one is sent before the
///   reading is saved to Core Data, so a refresh on it reads the readings without it. `glucoseStatsChanged` comes after
///   the save and after the cache dropped what the change touched.
/// - On every change, cancel the refresh in flight and start a new one, and drop its result when `Task.isCancelled`
///   after the await. Cancelling doesn't stop a call already running here, so without the check a slow (90-day)
///   result can overwrite a newer one. (Home runs one at a time instead, with one pending.)
/// - Nothing refreshes with the time alone: a result is as of its request (Home on the next change, midnight or the
///   foreground; Statistics on an interaction or the foreground).
/// - Subscribe with the `observe` / `observeUI` helpers, which hop off: `glucoseStatsChanged` is sent from this actor,
///   so a plain `sink` runs inline on it. Never do synchronous work in a sink of it.
actor GlucoseStatistics: AppService, LifetimeOwner {
    enum Config {
        /// read before every window and day: the cadence and the previous reading's span
        static let lookback: TimeInterval = .hours(1)
        /// read after a day: its last reading's span
        static let lookahead: TimeInterval = .minutes(10)
        /// a reading coming in can change the span of the readings this much before it
        static let appendReach: TimeInterval = .minutes(10)
        /// a backfill, delete or recalibration can change the cadence this far around it
        static let changeReach: TimeInterval = .hours(1)
        /// about 4.8 KB each
        static let maxCachedDays = 100
        /// beyond this the invalidation records are folded into `storeFloor`
        static let maxInvalidations = 400
    }

    let lifetime = Lifetime()

    private let appCoordinator: AppCoordinator
    private let source: GlucosePointSource
    private let calendar: @Sendable() -> Calendar
    private let now: @Sendable() -> Date

    /// the complete days (never today), keyed by their date in the calendar of `cacheIdentity`
    private var cache: [StatsDayKey: DayAggregate] = [:]
    private var cacheIdentity: StatsCalendarIdentity?
    /// bumped by every invalidation: a readings change, a time zone change
    private var generation = 0
    /// the generation each day was last invalidated at
    private var invalidated: [StatsDayKey: Int] = [:]
    /// nothing read before this generation is stored (everything was dropped at it)
    private var storeFloor = 0
    private var publishedSeq = 0

    /// open Statistics screens
    private var sessions = 0
    private var held: Held?
    private var lastHeldID = 0
    /// bumped whenever the held readings are dropped: an extension that started before can't bring them back
    private var heldEpoch = 0

    init(
        appCoordinator: AppCoordinator,
        source: GlucosePointSource,
        calendar: @escaping @Sendable() -> Calendar = { .autoupdatingCurrent },
        now: @escaping @Sendable() -> Date = { Date() }
    ) {
        self.appCoordinator = appCoordinator
        self.source = source
        self.calendar = calendar
        self.now = now
    }

    func start() async {
        observe(appCoordinator.readingsChanged) { me, change in
            await me.readingsChanged(change)
        }
        observe(notification: .NSSystemTimeZoneDidChange) { me in
            await me.timeZoneMayHaveChanged()
        }
        observe(notification: UIApplication.didEnterBackgroundNotification) { me in
            await me.dropHeld()
        }
        observe(notification: UIApplication.didReceiveMemoryWarningNotification) { me in
            await me.dropHeld()
        }
    }

    // MARK: - API

    // Consumers: refresh on `glucoseStatsChanged` only, cancel the refresh in flight on every change and drop a
    // cancelled result, subscribe through `observe` / `observeUI` (see the type's documentation).

    /// Home, Overview, and the AGP/Trace header numbers: the same code path for all of them.
    func summary(_ period: StatsPeriod, bands: StatsBands) async -> GlucoseSummary {
        await summary(period, bands: bands, tail: await readTail())
    }

    /// The rolling upload windows: the `duration` before E.
    func summary(rolling duration: TimeInterval, bands: StatsBands) async -> GlucoseSummary {
        await Self.summary(await aggregate(.rolling(duration), tail: await readTail()), period: nil, bands: bands)
    }

    /// The days of a period, as its summary sums them (the cache tests). The views (Daily, Weekly, the Day tab's
    /// selector) use `periodDays`: the same days with their window and the rule that gave its end.
    func days(_ period: StatsPeriod) async -> [DayAggregate] {
        await aggregate(.period(period), tail: await readTail()).days
    }

    /// The days of a period with their window and the rule that gave its end (Daily: the period's summary, from the same
    /// days, gives the time schedule).
    func periodDays(_ period: StatsPeriod) async -> PeriodDays {
        let aggregate = await aggregate(.period(period), tail: await readTail())
        return PeriodDays(window: aggregate.window, endRule: aggregate.endRule, days: aggregate.days)
    }

    func trace(_ range: TraceRange, bands: StatsBands) async -> TraceData {
        let tail = await readTail()
        let ctx = tail.ctx
        let domain: DateInterval
        let window: DateInterval
        switch range {
        case .last24h:
            window = Engine.window(for: .last24h, now: ctx.now, end: tail.end, calendar: ctx.calendar)
            domain = window
        case let .day(date):
            domain = StatsClock.wholeDay(of: date, calendar: ctx.calendar)
            window = DateInterval(start: domain.start, end: Swift.max(domain.start, Swift.min(domain.end, tail.end)))
        }
        let raw = await readings(Self.readRange(window, ctx), ctx, tail: tail.raw)
        return await Self.trace(raw.points, domain: domain, window: window, endRule: tail.endRule, bands: bands)
    }

    func agp(_ period: StatsPeriod) async -> [AGPBin?] {
        await agp(period, tail: await readTail())
    }

    /// The AGP tab's refresh: the profile, then the period's summary, from one tail read, so both have the same E.
    /// The summary reads the days the cache misses from the readings the profile holds (a session is open).
    func agp(_ period: StatsPeriod, bands: StatsBands) async -> (bins: [AGPBin?], summary: GlucoseSummary) {
        let tail = await readTail()
        let bins = await agp(period, tail: tail)
        let numbers = await summary(period, bands: bands, tail: await readTail(reusing: tail))
        return (bins, numbers)
    }

    func hourOfDay(_ period: StatsPeriod) async -> [HourBucket] {
        await hourOfDay(period, tail: await readTail())
    }

    /// The By hour tab's refresh: the 24 hours, then the period's summary, from one tail read (as the AGP tab's).
    func hourOfDay(_ period: StatsPeriod, bands: StatsBands) async -> (buckets: [HourBucket], summary: GlucoseSummary) {
        let tail = await readTail()
        let buckets = await hourOfDay(period, tail: tail)
        let numbers = await summary(period, bands: bands, tail: await readTail(reusing: tail))
        return (buckets, numbers)
    }

    /// By weekday: the readings of the `weeks` × 7 days to yesterday (`GlucoseStatsEngine.weekdayDays`) by weekday and
    /// clock hour, with the bands' seconds (`GlucoseStatsEngine.weekdayHours`). Held while a session is open, as By
    /// hour's.
    func weekdayHours(weeks: Int, bands: StatsBands) async -> WeekdayHours {
        let tail = await readTail()
        let ctx = tail.ctx
        let days = Engine.weekdayDays(weeks: weeks, today: ctx.today.start, calendar: ctx.calendar)
        guard let first = days.first, let last = days.last else {
            return Engine.weekdayHours([], days: [], bands: bands, calendar: ctx.calendar)
        }
        let window = DateInterval(start: first.start, end: last.end)
        let raw = await readings(Self.readRange(window, ctx), ctx, tail: tail.raw)
        var pooled = await Self.weekdayHours(raw.points, days: days, bands: bands, calendar: ctx.calendar)
        // a first day without readings: did the recording begin in the period, or is there one before it? One row
        // tells; a failed read doesn't claim a recording start
        if let firstDay = pooled.firstDayWithData, firstDay > window.start {
            do {
                pooled.hasReadingsBefore = try await source.fetchGlucosePoints(
                    from: .distantPast,
                    to: window.start,
                    limit: 1
                ).isNotEmpty
            } catch {
                warning(.service, "Glucose statistics: looking for a reading before By weekday's period failed", error: error)
                pooled.hasReadingsBefore = true
            }
        }
        return pooled
    }

    /// Statistics opened: the readings Trace, AGP and Hour of day read are held (and kept current) until it closes.
    func beginSession() {
        sessions += 1
    }

    func endSession() {
        sessions = Swift.max(sessions - 1, 0)
        if sessions == 0 {
            dropHeld()
        }
    }

    // MARK: - Changes

    /// Drops the cached days a change of the stored readings touched, splices it into the held readings,
    /// then tells the consumers. Runs one change at a time (the `readingsChanged` observer awaits it).
    func readingsChanged(_ change: ReadingsChange) async {
        let calendar = currentCalendar()
        generation += 1
        let changeGeneration = generation

        switch change {
        case .all:
            dropCache()
            dropHeld()
            publish(nil)

        case let .interval(interval, newest):
            // a reading coming in changes only the previous reading's span (and its own day);
            // anything else can change the cadence around it
            let dropped = newest
                ? DateInterval(start: interval.start.addingTimeInterval(-Config.appendReach), end: interval.end)
                : DateInterval(
                    start: interval.start.addingTimeInterval(-Config.changeReach),
                    end: interval.end.addingTimeInterval(Config.changeReach)
                )
            invalidate(dropped, calendar: calendar)
            await splice(
                DateInterval(
                    start: interval.start.addingTimeInterval(-Config.changeReach),
                    end: interval.end.addingTimeInterval(Config.changeReach)
                ),
                generation: changeGeneration
            )
            publish(dropped)
        }
    }

    private func timeZoneMayHaveChanged() {
        _ = currentCalendar()
    }

    private func dropHeld() {
        held = nil
        heldEpoch += 1
    }

    private func invalidate(_ span: DateInterval, calendar: Calendar) {
        for day in StatsClock.calendarDays(in: span, calendar: calendar) {
            let key = StatsDayKey(day.start, calendar)
            cache[key] = nil
            invalidated[key] = generation
        }
        if invalidated.count > Config.maxInvalidations {
            invalidated.removeAll()
            storeFloor = generation
        }
    }

    private func dropCache() {
        cache.removeAll()
        invalidated.removeAll()
        storeFloor = generation
    }

    /// Re-reads the changed range of the held readings. When that fails they are dropped: they would miss the change.
    ///
    /// Raising `asOf` to the change is right because the held readings reflect every earlier readings change: one is
    /// kept only when it reflects the generation it is kept at (`hold`), and every change after that splices it, one at
    /// a time. A generation it may lag behind by is a time zone change, which changes no readings.
    private func splice(_ range: DateInterval, generation changeGeneration: Int) async {
        guard var current = held else { return }
        guard let range = range.intersection(with: current.range), range.duration > 0 else {
            // the change is outside them
            current.asOf = Swift.max(current.asOf, changeGeneration)
            current.version += 1
            held = current
            return
        }

        let fetched: [GlucosePoint]
        do {
            fetched = try await source.fetchGlucosePoints(from: range.start, to: range.end)
        } catch {
            warning(.service, "Glucose statistics: re-reading the changed readings failed", error: error)
            if held?.id == current.id {
                dropHeld()
            }
            return
        }
        let points = await Self.cleaned(fetched)

        // dropped or replaced meanwhile
        guard var spliced = held, spliced.id == current.id else { return }
        spliced.replace(range, with: points)
        spliced.asOf = Swift.max(spliced.asOf, changeGeneration)
        spliced.version += 1
        held = spliced
    }

    private func publish(_ interval: DateInterval?) {
        publishedSeq += 1
        appCoordinator.setGlucoseStatsChanged(StatsChange(seq: publishedSeq, interval: interval))
    }

    // MARK: - Context

    private struct Context: Sendable {
        /// frozen for the request
        let calendar: Calendar
        let now: Date
        let today: DateInterval

        var identity: StatsCalendarIdentity { StatsCalendarIdentity(calendar) }

        /// read first by every request: today (E comes from it), with the lookback before it.
        /// Up to the end of today, not `now`: a future-dated reading is always in or always out.
        var tailRange: DateInterval {
            DateInterval(start: today.start.addingTimeInterval(-Config.lookback), end: today.end)
        }
    }

    private func context() -> Context {
        let calendar = currentCalendar()
        let now = self.now()
        return Context(calendar: calendar, now: now, today: StatsClock.wholeDay(of: now, calendar: calendar))
    }

    /// The calendar, frozen: an autoupdating one could change its time zone halfway through a request.
    /// A new time zone (or calendar) drops the cache, whose days are dates in the old one.
    private func currentCalendar() -> Calendar {
        let calendar = StatsClock.frozen(self.calendar())
        let identity = StatsCalendarIdentity(calendar)
        if let cacheIdentity, cacheIdentity != identity {
            let previous = generation
            generation += 1
            dropCache()
            self.cacheIdentity = identity
            // the held readings are absolute times: still valid, and still as current as they were (unless a splice
            // is in flight: it raises them when it lands, and the days read from them are stored after the next change)
            if var current = held, current.asOf == previous {
                current.asOf = generation
                current.version += 1
                held = current
            }
            publish(nil)
        } else {
            cacheIdentity = identity
        }
        return calendar
    }

    // MARK: - Days

    private enum Span: Sendable {
        case period(StatsPeriod)
        /// the duration before E
        case rolling(TimeInterval)
    }

    private struct Aggregate: Sendable {
        let window: DateInterval
        let endRule: StatsEndRule
        let days: [DayAggregate]
    }

    private func summary(_ period: StatsPeriod, bands: StatsBands, tail: Tail) async -> GlucoseSummary {
        await Self.summary(await aggregate(.period(period), tail: tail), period: period, bands: bands)
    }

    /// The window and its days. The day list comes from the engine, the complete days from the cache, the others
    /// (today, partial days) from the readings.
    private func aggregate(_ span: Span, tail: Tail) async -> Aggregate {
        let ctx = tail.ctx
        let end = tail.end

        let window: DateInterval
        let days: [DateInterval]
        switch span {
        case let .period(period):
            window = Engine.window(for: period, now: ctx.now, end: end, calendar: ctx.calendar)
            days = Engine.days(for: period, window: window, calendar: ctx.calendar)
        case let .rolling(duration):
            window = DateInterval(start: end.addingTimeInterval(-Swift.max(duration, 0)), end: end)
            days = Engine.days(in: window, calendar: ctx.calendar)
        }

        return Aggregate(window: window, endRule: tail.endRule, days: await dayAggregates(days, ctx, tail: tail.raw))
    }

    private func agp(_ period: StatsPeriod, tail: Tail) async -> [AGPBin?] {
        let ctx = tail.ctx
        let window = Engine.window(for: period, now: ctx.now, end: tail.end, calendar: ctx.calendar)
        let raw = await readings(Self.readRange(window, ctx), ctx, tail: tail.raw)
        return await Self.agp(raw.points, calendar: ctx.calendar, window: window)
    }

    private func hourOfDay(_ period: StatsPeriod, tail: Tail) async -> [HourBucket] {
        let ctx = tail.ctx
        let window = Engine.window(for: period, now: ctx.now, end: tail.end, calendar: ctx.calendar)
        let raw = await readings(Self.readRange(window, ctx), ctx, tail: tail.raw)
        return await Self.hourOfDay(raw.points, calendar: ctx.calendar, window: window)
    }

    private func dayAggregates(_ days: [DateInterval], _ ctx: Context, tail: Raw) async -> [DayAggregate] {
        var result: [DayAggregate?] = days.map { cached($0, ctx) }

        for run in StatsIntervals.runs(result.indices.filter { result[$0] == nil }) {
            let runDays = run.map { days[$0] }
            let first = runDays[0]
            let last = runDays[runDays.count - 1]
            let range = DateInterval(
                start: first.start.addingTimeInterval(-Config.lookback),
                end: Swift.min(last.end.addingTimeInterval(Config.lookahead), ctx.today.end)
            )
            let raw = await read(range, reusing: tail, ctx)
            let computed = await Self.aggregates(raw.points, days: runDays)
            for (index, aggregate) in zip(run, computed) {
                result[index] = aggregate
                store(aggregate, ctx, asOf: raw.asOf)
            }
        }

        evict()
        return result.compactMap { $0 }
    }

    /// A complete calendar day before today; only those are cached.
    private func cacheKey(_ day: DateInterval, _ ctx: Context) -> StatsDayKey? {
        guard day.end <= ctx.today.start, day == StatsClock.wholeDay(of: day.start, calendar: ctx.calendar) else { return nil }
        return StatsDayKey(day.start, ctx.calendar)
    }

    private func cached(_ day: DateInterval, _ ctx: Context) -> DayAggregate? {
        guard ctx.identity == cacheIdentity, let key = cacheKey(day, ctx) else { return nil }
        return cache[key]
    }

    /// - Parameter asOf: nil (a failed read) is never stored
    private func store(_ aggregate: DayAggregate, _ ctx: Context, asOf: Int?) {
        guard ctx.identity == cacheIdentity,
              let asOf,
              asOf >= storeFloor,
              let key = cacheKey(aggregate.day, ctx),
              (invalidated[key] ?? Int.min) <= asOf
        else { return }
        cache[key] = aggregate
    }

    private func evict() {
        guard cache.count > Config.maxCachedDays else { return }
        for key in cache.keys.sorted().prefix(cache.count - Config.maxCachedDays) {
            cache[key] = nil
        }
    }

    // MARK: - Readings

    /// Readings as read, not yet cleaned, and the generation they reflect.
    private struct Raw: Sendable {
        let points: [GlucosePoint]
        /// nil when a read failed: the points miss what it should have read, and nothing computed from them is stored
        let asOf: Int?
    }

    /// The readings Statistics works on while it is open: the largest range asked for so far, up to the end of today,
    /// kept current by splicing in what changes.
    private struct Held: Sendable {
        let id: Int
        /// bumped by every change of them (a splice, an extension, a raised `asOf`): an extension built from an older
        /// version isn't kept
        var version = 0
        var range: DateInterval
        /// clean, oldest -> newest
        var points: [GlucosePoint]
        /// every invalidation up to this generation is reflected
        var asOf: Int

        func covers(_ range: DateInterval) -> Bool {
            self.range.start <= range.start && range.end <= self.range.end
        }

        func points(in range: DateInterval) -> [GlucosePoint] {
            Array(points[index(range.start) ..< index(range.end)])
        }

        /// - Parameter new: clean, all inside the range
        mutating func replace(_ range: DateInterval, with new: [GlucosePoint]) {
            points.replaceSubrange(index(range.start) ..< index(range.end), with: new)
        }

        /// the first point at or after the date
        private func index(_ date: Date) -> Int {
            points.partitionIndex { $0.time >= date }
        }
    }

    /// What a request reads first, in its frozen context: the tail, and E from it (with the rule that gave it).
    private struct Tail: Sendable {
        let ctx: Context
        let raw: Raw
        let end: Date
        let endRule: StatsEndRule
    }

    /// A new context, and its tail.
    private func readTail() async -> Tail {
        let ctx = context()
        let tail = await read(ctx.tailRange)
        let end = await Self.effectiveEnd(tail.points, ctx)
        return Tail(ctx: ctx, raw: tail, end: end.end, endRule: end.rule)
    }

    /// The tail of an earlier request of the same refresh (its context, its E), for the next request: only while it
    /// reflects every invalidation so far, otherwise read again, as a request of its own would. So never a tail read
    /// before a readings change, a wipe or a time zone change (noticed here as at the start of a request), nor a failed
    /// one (no `asOf`), nor one from held readings a splice in flight hasn't caught up yet. Lives only for the call.
    private func readTail(reusing shared: Tail) async -> Tail {
        _ = currentCalendar()
        guard let asOf = shared.raw.asOf, asOf == generation else { return await readTail() }
        return shared
    }

    /// From the held readings when they cover the range, otherwise fetched.
    private func read(_ range: DateInterval) async -> Raw {
        if let held, held.covers(range) {
            return Raw(points: held.points(in: range), asOf: held.asOf)
        }
        let asOf = generation
        guard range.duration > 0 else { return Raw(points: [], asOf: asOf) }
        do {
            return Raw(points: try await source.fetchGlucosePoints(from: range.start, to: range.end), asOf: asOf)
        } catch {
            warning(.service, "Glucose statistics: reading the readings failed", error: error)
            return Raw(points: [], asOf: nil)
        }
    }

    /// Like `read`, taking the part inside the tail from the tail.
    /// - Parameter range: ends no later than the end of today
    private func read(_ range: DateInterval, reusing tail: Raw, _ ctx: Context) async -> Raw {
        let tailRange = ctx.tailRange
        guard range.end > tailRange.start else { return await read(range) }

        let fromTail = tail.points.filter { $0.time >= range.start && $0.time < range.end }
        guard range.start < tailRange.start else { return Raw(points: fromTail, asOf: tail.asOf) }

        let head = await read(DateInterval(start: range.start, end: tailRange.start))
        return Raw(points: head.points + fromTail, asOf: Self.older(head.asOf, tail.asOf))
    }

    /// The readings Trace, AGP and Hour of day work on: held while a session is open.
    private func readings(_ range: DateInterval, _ ctx: Context, tail: Raw) async -> Raw {
        guard range.duration > 0 else { return Raw(points: [], asOf: generation) }
        guard sessions > 0 else { return await read(range, reusing: tail, ctx) }
        return await hold(range, ctx, tail: tail)
    }

    /// Extends the held readings to the range (and on to the end of today), reading only what they miss.
    private func hold(_ range: DateInterval, _ ctx: Context, tail: Raw) async -> Raw {
        let wanted = DateInterval(start: range.start, end: Swift.max(range.end, ctx.today.end))
        let base = held
        if let base, base.covers(wanted) {
            return Raw(points: base.points(in: range), asOf: base.asOf)
        }

        let startEpoch = heldEpoch
        var merged: Held
        var missing: [DateInterval]
        if let base {
            merged = base
            missing = [
                DateInterval(start: wanted.start, end: Swift.max(wanted.start, base.range.start)),
                DateInterval(start: Swift.min(base.range.end, wanted.end), end: wanted.end)
            ].filter { $0.duration > 0 }
        } else {
            lastHeldID += 1
            merged = Held(id: lastHeldID, range: wanted, points: [], asOf: .max)
            missing = [wanted]
        }

        var failed = false
        for part in missing {
            let raw = await read(part, reusing: tail, ctx)
            guard let asOf = raw.asOf else {
                failed = true
                break
            }
            let points = await Self.cleaned(raw.points)
            merged.replace(part, with: points)
            merged.asOf = Swift.min(merged.asOf, asOf)
        }
        merged.range = DateInterval(
            start: Swift.min(merged.range.start, wanted.start),
            end: Swift.max(merged.range.end, wanted.end)
        )
        merged.version += 1

        // Kept only when every read went through, it reflects the current generation (nothing it was built from is
        // older, e.g. a tail read before a change, and nothing changed meanwhile: a read could have missed it), the
        // held readings it extends are still the same version (a splice landing meanwhile isn't overwritten), and they
        // weren't dropped meanwhile (closing Statistics, background, memory warning). This request gets its readings
        // either way.
        if !failed, sessions > 0, heldEpoch == startEpoch, merged.asOf == generation,
           held?.id == base?.id, held?.version == base?.version
        {
            held = merged
        }
        return Raw(points: merged.points(in: range), asOf: failed ? nil : merged.asOf)
    }

    // MARK: - Computation (static, so it runs off the actor)

    private static func cleaned(_ points: [GlucosePoint]) async -> [GlucosePoint] {
        Engine.clean(points)
    }

    private static func effectiveEnd(_ points: [GlucosePoint], _ ctx: Context) async -> (end: Date, rule: StatsEndRule) {
        Engine.effectiveEndRule(Engine.weigh(Engine.clean(points)), now: ctx.now, calendar: ctx.calendar)
    }

    private static func aggregates(_ points: [GlucosePoint], days: [DateInterval]) async -> [DayAggregate] {
        Engine.dayAggregates(Engine.weigh(Engine.clean(points)), days: days)
    }

    /// The summary of the summed days: they add up to the window.
    private static func summary(_ aggregate: Aggregate, period: StatsPeriod?, bands: StatsBands) async -> GlucoseSummary {
        Engine.summary(days: aggregate.days, window: aggregate.window, endRule: aggregate.endRule, period: period, bands: bands)
    }

    private static func trace(
        _ points: [GlucosePoint],
        domain: DateInterval,
        window: DateInterval,
        endRule: StatsEndRule,
        bands: StatsBands
    ) async -> TraceData {
        let w = Engine.weigh(Engine.clean(points))
        let histogram = Engine.histogram(w, clippedTo: window)
        // a day, or the 24 hours: one day either way
        let counts = Engine.dayCounts(.today, days: [DayAggregate(day: window, histogram: histogram)])
        return TraceData(
            domain: domain,
            window: window,
            points: w.filter { $0.time >= window.start && $0.time < window.end },
            summary: Engine.summary(
                histogram,
                window: window,
                endRule: endRule,
                calendarDays: counts.calendarDays,
                daysWithData: counts.daysWithData,
                bands: bands
            )
        )
    }

    private static func agp(_ points: [GlucosePoint], calendar: Calendar, window: DateInterval) async -> [AGPBin?] {
        Engine.agp(Engine.weigh(Engine.clean(points)), calendar: calendar, clippedTo: window)
    }

    private static func hourOfDay(_ points: [GlucosePoint], calendar: Calendar, window: DateInterval) async -> [HourBucket] {
        Engine.hourOfDay(Engine.weigh(Engine.clean(points)), calendar: calendar, clippedTo: window)
    }

    private static func weekdayHours(
        _ points: [GlucosePoint],
        days: [DateInterval],
        bands: StatsBands,
        calendar: Calendar
    ) async -> WeekdayHours {
        Engine.weekdayHours(Engine.weigh(Engine.clean(points)), days: days, bands: bands, calendar: calendar)
    }

    // MARK: - Helpers

    /// The window's readings: the lookback before it, the lookahead after it (never past the end of today).
    private static func readRange(_ window: DateInterval, _ ctx: Context) -> DateInterval {
        let start = window.start.addingTimeInterval(-Config.lookback)
        return DateInterval(
            start: start,
            end: Swift.max(start, Swift.min(window.end.addingTimeInterval(Config.lookahead), ctx.today.end))
        )
    }

    /// The older of two generations; a failed read (nil) is older than any.
    private static func older(_ a: Int?, _ b: Int?) -> Int? {
        guard let a, let b else { return nil }
        return Swift.min(a, b)
    }
}
