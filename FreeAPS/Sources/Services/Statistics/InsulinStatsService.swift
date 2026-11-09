import Foundation
import UIKit

private typealias Engine = InsulinStatsEngine

/// Where the insulin statistics read from: `CoreDataStorage`, a wrapper of it in the tests. Every fetch throws when it
/// (or any part of it) couldn't be read: nothing computed from a failed read is cached or shown as "no pump data".
protocol InsulinDataSource: Sendable {
    /// The events of both sources (no coverage rows), `date` in `[from, to)`, oldest -> newest.
    func fetchPumpEvents(from: Date, to: Date) async throws -> [PumpEventRecord]
    /// The state running into `date`: the events from the newest temp basal before it on (without one, from the
    /// newest suspend or resume on), up to `date` (excluded), oldest -> newest.
    func fetchPumpEventsRunningInto(_ date: Date) async throws -> [PumpEventRecord]
    /// The pump sessions' covered time (both sources) and the pump's local time inside `[from, to)`, clipped to it
    /// (`CoreDataStorage.fetchCoverage`).
    func fetchCoverage(from: Date, to: Date) async throws -> [CoveredInterval]
    /// The schedule records in effect during `[from, to)`: the newest at or before `from` (without one, the oldest
    /// record), then the later ones before `to`, oldest -> newest.
    func fetchBasalSchedules(from: Date, to: Date) async throws -> [BasalScheduleRecordValue]
    /// The `Reasons` IOB, `[from, to)`, oldest -> newest.
    func fetchIOBPoints(from: Date, to: Date) async throws -> [IOBPoint]
}

/// The Insulin tab's numbers: reads the pump events, coverage, basal schedules and IOB and runs `InsulinStatsEngine`
/// off the main thread, with a cache of the complete days (their 24 hours and IOB time with them), so a refresh after a
/// loop reads only today.
///
/// - **Cache:** complete calendar days only (never today), keyed by their date in the calendar of `cacheIdentity`
///   (its identifier and time zone), at most `Config.maxCachedDays`. A day is computed the same whether it is read
///   alone or in a run with others: every run reads the state running into it and `Config.lookahead` after it.
/// - **Invalidation:** `insulinDataChanged` (sent by the writers after their save) `.interval(i)` drops the days
///   touching `[i.start - 1 h, i.end + 1 h]` (a temp clipped by the next one, the running-into state of the next day,
///   an IOB row's span); `.all` and a time zone change drop everything. A basal profile edit comes as the store's
///   `.interval([edit, now])`: only today (never cached) and, in the hour after midnight, yesterday. A memory warning
///   drops the cache (nothing changed: nothing is published).
/// - **"Profile assumed" days** (covered time before the oldest schedule record) depend on which record is the oldest,
///   which a Nightscout schedule import can change without touching them. A cached one is used only while the oldest
///   record is still the one it was computed with: its date and its entries (a re-import can change them in place).
///   Days read while no schedule record exists at all (nothing is filled) are not cached: the first record changes
///   every day.
/// - **Staleness:** every invalidation bumps `generation`. A request reads with the generation it started at (`asOf`);
///   a day it computed is stored only when the day wasn't invalidated after that, `asOf` isn't below `storeFloor` (set
///   by `.all`, a time zone change, or folding the invalidation marks), and the time zone still matches. So a day
///   invalidated while it was being read is returned, but not stored (the glucose service's rule, without held
///   readings). A failed read throws: nothing from it is stored, nothing is shown from it. Two requests for the same
///   missing days each read them: no joining of reads in flight (`statistics-rework-plan.md` §4.4, "No joining").
/// - After an invalidation `appCoordinator.insulinStatsChanged` is published (one sender, `seq` + 1 each). Consumers:
///   the glucose service's contract (refresh on it only, cancel the refresh in flight, subscribe with `observe` /
///   `observeUI`: it is sent from this actor).
///
/// The actor holds only the cache state; the engine runs in static (so nonisolated) async helpers on value snapshots.
actor InsulinStatsService: AppService, LifetimeOwner {
    enum Config {
        /// a change of the stored rows can change the days this far around it: a temp clipped by the next one, the
        /// running-into state of the next day, the span of the IOB row before it
        static let changeReach: TimeInterval = .hours(1)
        /// read after a run of days: the next temp (it can clip one running over midnight), the next IOB row (the span
        /// of the last one); what is after the days counts nowhere
        static let lookahead: TimeInterval = .hours(1)
        /// IOB rows read before a run: the last one before midnight stands for time after it
        static let iobLookback: TimeInterval = InsulinStatsEngine.iobMaximumSpan + InsulinStatsEngine.iobDuplicateWindow
        /// a few KB each (24 hours)
        static let maxCachedDays = 100
        /// beyond this the invalidation marks are folded into `storeFloor`
        static let maxInvalidations = 400
    }

    let lifetime = Lifetime()

    private let appCoordinator: AppCoordinator
    private let source: InsulinDataSource
    private let calendar: @Sendable() -> Calendar
    private let now: @Sendable() -> Date

    /// the complete days (never today), keyed by their date in the calendar of `cacheIdentity`
    private var cache: [StatsDayKey: CachedDay] = [:]
    private var cacheIdentity: StatsCalendarIdentity?
    /// bumped by every invalidation: an insulin data change, a time zone change
    private var generation = 0
    /// the generation each day was last invalidated at
    private var invalidated: [StatsDayKey: Int] = [:]
    /// nothing read before this generation is stored (everything was dropped at it)
    private var storeFloor = 0
    private var publishedSeq = 0

    init(
        appCoordinator: AppCoordinator,
        source: InsulinDataSource,
        calendar: @escaping @Sendable() -> Calendar = { .autoupdatingCurrent },
        now: @escaping @Sendable() -> Date = { Date() }
    ) {
        self.appCoordinator = appCoordinator
        self.source = source
        self.calendar = calendar
        self.now = now
    }

    func start() async {
        observe(appCoordinator.insulinDataChanged) { me, change in
            await me.insulinDataChanged(change)
        }
        observe(notification: .NSSystemTimeZoneDidChange) { me in
            await me.timeZoneMayHaveChanged()
        }
        observe(notification: UIApplication.didReceiveMemoryWarningNotification) { me in
            await me.memoryWarning()
        }
    }

    // MARK: - API

    /// The period's days (today "so far"), the summary (rule a) and the hours, as `InsulinStatsEngine.period` gives
    /// them from the raw rows. For the N-day periods (the Insulin tab computes 7/14/30/90 d): the callers map Today and
    /// 24 h first (`InsulinStatsEngine.periodDays`); the Insulin tab's Today reads `today()`.
    /// - Throws: when a read failed (nothing from it is cached)
    func period(_ period: StatsPeriod) async throws -> InsulinPeriod {
        let ctx = context()
        let days = try await self.days(Engine.periodDays(period, now: ctx.now, calendar: ctx.calendar), ctx)
        return await Self.period(days, period: period)
    }

    /// The last `count` calendar days, oldest -> newest, the last one today ("so far"), as `period` reads them (the
    /// complete ones from the cache): `InsulinStatsEngine.days(InsulinStatsEngine.lastDays(count, ...), ...)` from the
    /// raw rows. Home's insulin card: the 7 days before today and today (a 7 d period is 6 and today).
    /// - Throws: when a read failed (nothing from it is cached)
    func days(last count: Int) async throws -> [DayInsulin] {
        let ctx = context()
        return try await self.days(Engine.lastDays(count, now: ctx.now, calendar: ctx.calendar), ctx)
    }

    /// The whole calendar days given (none of them today), oldest -> newest, as `period` reads them (the complete ones
    /// from the cache): Statistics' Good & bad days, the days its glucose is scored for.
    /// - Throws: when a read failed (nothing from it is cached)
    func days(_ days: [DateInterval]) async throws -> [DayInsulin] {
        try await self.days(days, context())
    }

    /// Statistics › Insulin › Today: the `InsulinStatsEngine.usualDays` days before today and today (`days(last:)`,
    /// Home's insulin card's days), the summary over them (no period: its calendar days are the days read) and the
    /// hours. So Today's usual by now is over the same 7 days as Home's, their complete ones (a 7 d period is 6 and
    /// today).
    /// - Throws: when a read failed (nothing from it is cached)
    func today() async throws -> InsulinPeriod {
        let days = try await self.days(last: Engine.usualDays + 1)
        return await Self.period(days, period: nil)
    }

    /// The whole calendar days, oldest -> newest: the cached ones, the others read in runs and stored.
    private func days(_ days: [DateInterval], _ ctx: Context) async throws -> [DayInsulin] {
        let asOf = generation
        guard let first = days.first else { return [] }

        // one read for every run: the same records in effect, and the same oldest one
        let schedules = try await source.fetchBasalSchedules(from: first.start, to: ctx.today.end)
        let usable = schedules.filter(\.entries.isNotEmpty)
        // the record the time before it is assumed from, when one of the days can have such time; nil when a record is
        // in effect from the first day's start on (no day of them is "Profile assumed" then)
        let assumedFrom = AssumedSchedule.oldest(usable, after: first.start)

        var result: [DayInsulin?] = days.map { cached($0, ctx, assumedFrom: assumedFrom) }
        for run in StatsIntervals.runs(result.indices.filter { result[$0] == nil }) {
            let runDays = run.map { days[$0] }
            let input = try await read(runDays, schedules: schedules, ctx)
            let computed = await Self.days(runDays, input: input, now: ctx.now, calendar: ctx.calendar)
            for (index, day) in zip(run, computed) {
                result[index] = day
                // without any record nothing is filled: the first one changes every day
                if usable.isNotEmpty {
                    store(day, ctx, asOf: asOf, assumedFrom: assumedFrom)
                }
            }
        }

        evict()
        return result.compactMap { $0 }
    }

    // MARK: - Changes

    /// Drops the cached days a change of the stored insulin data touched, then tells the consumers.
    func insulinDataChanged(_ change: InsulinDataChange) {
        let calendar = currentCalendar()
        generation += 1

        switch change {
        case .all:
            dropCache()
            publish(nil)

        case let .interval(interval):
            let dropped = DateInterval(
                start: interval.start.addingTimeInterval(-Config.changeReach),
                end: interval.end.addingTimeInterval(Config.changeReach)
            )
            invalidate(dropped, calendar: calendar)
            publish(dropped)
        }
    }

    /// A memory warning: the cache goes (nothing changed, so nothing is published).
    func memoryWarning() {
        cache.removeAll()
    }

    private func timeZoneMayHaveChanged() {
        _ = currentCalendar()
    }

    /// Marks the days touching the span (for the reads in flight) and drops them. Only the days a request can ask for
    /// are marked (the last `maxCachedDays` and a margin): a span can start in the distant past. Every cached day
    /// touching it goes either way.
    private func invalidate(_ span: DateInterval, calendar: Calendar) {
        for (key, cached) in cache where cached.day.day.start < span.end && span.start < cached.day.day.end {
            cache[key] = nil
        }

        let today = calendar.startOfDay(for: now())
        let earliest = calendar.date(byAdding: .day, value: -(Config.maxCachedDays + 2), to: today)
            ?? today.addingTimeInterval(-.days(Config.maxCachedDays + 2))
        let latest = calendar.date(byAdding: .day, value: 2, to: today) ?? today.addingTimeInterval(.days(2))
        let start = Swift.max(span.start, earliest)
        let end = Swift.min(span.end, latest)
        if start <= end {
            for day in StatsClock.calendarDays(in: DateInterval(start: start, end: end), calendar: calendar) {
                let key = StatsDayKey(day.start, calendar)
                cache[key] = nil
                invalidated[key] = generation
            }
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

    private func publish(_ interval: DateInterval?) {
        publishedSeq += 1
        appCoordinator.setInsulinStatsChanged(StatsChange(seq: publishedSeq, interval: interval))
    }

    // MARK: - Context

    private struct Context: Sendable {
        /// frozen for the request
        let calendar: Calendar
        let now: Date
        /// the whole calendar day of `now`
        let today: DateInterval

        var identity: StatsCalendarIdentity { StatsCalendarIdentity(calendar) }
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
            generation += 1
            dropCache()
            self.cacheIdentity = identity
            publish(nil)
        } else {
            cacheIdentity = identity
        }
        return calendar
    }

    // MARK: - Days

    /// A complete calendar day before today; only those are cached.
    private func cacheKey(_ day: DateInterval, _ ctx: Context) -> StatsDayKey? {
        guard day.end <= ctx.today.start, day == StatsClock.wholeDay(of: day.start, calendar: ctx.calendar) else { return nil }
        return StatsDayKey(day.start, ctx.calendar)
    }

    /// A cached day, and the oldest record its "Profile assumed" time used (nil: it has none).
    private struct CachedDay: Sendable {
        let day: DayInsulin
        let assumedFrom: AssumedSchedule?
    }

    /// - Parameter assumedFrom: the oldest schedule record, when the request's days can be before it: a "Profile
    ///   assumed" day computed with another oldest record (another date, or other entries) is stale
    private func cached(_ day: DateInterval, _ ctx: Context, assumedFrom: AssumedSchedule?) -> DayInsulin? {
        guard ctx.identity == cacheIdentity, let key = cacheKey(day, ctx), let cached = cache[key] else { return nil }
        if cached.day.profileAssumed, cached.assumedFrom != assumedFrom {
            cache[key] = nil
            return nil
        }
        return cached.day
    }

    private func store(_ day: DayInsulin, _ ctx: Context, asOf: Int, assumedFrom: AssumedSchedule?) {
        guard ctx.identity == cacheIdentity,
              asOf >= storeFloor,
              let key = cacheKey(day.day, ctx),
              (invalidated[key] ?? Int.min) <= asOf
        else { return }
        cache[key] = CachedDay(day: day, assumedFrom: day.profileAssumed ? assumedFrom : nil)
    }

    private func evict() {
        guard cache.count > Config.maxCachedDays else { return }
        for key in cache.keys.sorted().prefix(cache.count - Config.maxCachedDays) {
            cache[key] = nil
        }
    }

    /// The rows of a run of consecutive days: the state running into it, the events and IOB up to `lookahead` after it
    /// (never past the end of today), the coverage from the state's first event on (the engine drops a Nightscout event
    /// inside the pump's coverage there too), and the period's schedule records.
    private func read(_ days: [DateInterval], schedules: [BasalScheduleRecordValue], _ ctx: Context) async throws
        -> InsulinInput
    {
        let source = self.source
        let from = days[0].start
        let to = Swift.max(from, Swift.min(days[days.count - 1].end.addingTimeInterval(Config.lookahead), ctx.today.end))
        async let events = source.fetchPumpEvents(from: from, to: to)
        async let iob = source.fetchIOBPoints(from: from.addingTimeInterval(-Config.iobLookback), to: to)
        do {
            let runningInto = try await source.fetchPumpEventsRunningInto(from)
            let coverage = try await source.fetchCoverage(
                from: Swift.min(runningInto.first?.date ?? from, from),
                to: to
            )
            return try await InsulinInput(
                events: runningInto + events,
                coverage: coverage,
                schedules: schedules,
                iob: iob
            )
        } catch {
            warning(.service, "Insulin statistics: reading the insulin data failed", error: error)
            throw error
        }
    }

    // MARK: - Computation (static, so it runs off the actor)

    private static func days(_ days: [DateInterval], input: InsulinInput, now: Date, calendar: Calendar) async -> [DayInsulin] {
        Engine.days(days, input: input, now: now, calendar: calendar)
    }

    private static func period(_ days: [DayInsulin], period: StatsPeriod?) async -> InsulinPeriod {
        InsulinPeriod(summary: Engine.summary(days, period: period), days: days, hours: Engine.hours(days))
    }
}
