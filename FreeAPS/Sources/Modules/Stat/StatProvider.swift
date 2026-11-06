import Foundation
import Swinject

extension Stat {
    final class Provider: StatProvider, Sendable {
        private let statistics: GlucoseStatistics
        private let insulinStatistics: InsulinStatsService
        private let coreDataStorage = CoreDataStorage()
        /// the Patches topic's sessions, for the key they were computed for
        private let patchesCache = PatchesCache()

        required init(resolver: Resolver) {
            statistics = resolver.resolve(GlucoseStatistics.self)!
            insulinStatistics = resolver.resolve(InsulinStatsService.self)!
        }

        func summary(_ period: StatsPeriod, bands: StatsBands) async -> GlucoseSummary {
            await statistics.summary(period, bands: bands)
        }

        /// The trace, computed here, off the main actor. Without the selector's days (`traceSelector`): a cold read of
        /// 90 days must not hold up today's trace.
        func trace(_ range: TraceRange, bands: StatsBands) async -> TraceResult {
            Self.traceResult(await statistics.trace(range, bands: bands), range: range, bands: bands)
        }

        /// The Day tab's selector: the last 90 days (the complete ones from the day cache) with their in-range bars, and
        /// the 24 hours, formatted here, off the main actor.
        func traceSelector(bands: StatsBands) async -> [TraceSelectorItem] {
            Self.traceSelector(await statistics.periodDays(TraceDay.selectorPeriod), bands: bands)
        }

        /// The Day tab's usual day: the AGP tab's profile and summary for the period (one call, one tail read), without
        /// its plot points: the overlay is placed on the shown day's axis (`UsualDayOverlay`).
        func usualDay(_ period: StatsPeriod, bands: StatsBands) async -> UsualDayResult {
            let result = await statistics.agp(period, bands: bands)
            return UsualDayResult(period: period, bins: result.bins, summary: result.summary)
        }

        /// The profile and the period's summary, ready to draw: computed here, off the main actor.
        /// One call: one tail read (one E) for both, the profile first: it holds the period's readings (a session is
        /// open), so the summary reads the days the cache misses from them; at once, both would fetch them.
        func agp(_ period: StatsPeriod, bands: StatsBands) async -> AGPResult {
            let result = await statistics.agp(period, bands: bands)
            return Self.agpResult(result.bins, summary: result.summary)
        }

        /// The period's days, ready to draw, and its summary: computed here, off the main actor. One read: the summary is
        /// the days summed, as the service sums them for the Overview.
        func daily(_ period: StatsPeriod, bands: StatsBands) async -> DailyResult {
            Self.dailyResult(await statistics.periodDays(period), period: period, bands: bands)
        }

        /// The 24 hours and the period's summary, ready to draw: computed here, off the main actor. One call, as the
        /// AGP's: one tail read for both, the hours first (they hold the period's readings, a session is open), so the
        /// summary reads the days the cache misses from them.
        func hourOfDay(_ period: StatsPeriod, bands: StatsBands) async -> HourOfDayResult {
            let result = await statistics.hourOfDay(period, bands: bands)
            return HourOfDayResult(buckets: result.buckets, summary: result.summary, bands: bands)
        }

        /// By weekday: the whole weeks to yesterday pooled by weekday and hour, then the pools shown, in the columns'
        /// order: computed here, off the main actor.
        func weekday(_ period: StatsPeriod, bands: StatsBands) async -> WeekdayResult {
            let pooled = await statistics.weekdayHours(weeks: period.weekCount ?? 0, bands: bands)
            return WeekdayResult(pooled, period: period)
        }

        /// The period's weeks against the period, ready to draw, and its summary: computed here, off the main actor. One
        /// read, as the Daily view's: the weeks are the period's days summed by seven, the summary all of them.
        func weekly(_ period: StatsPeriod, bands: StatsBands, units: GlucoseUnits) async -> WeeklyResult {
            Self.weeklyResult(await statistics.periodDays(period), period: period, bands: bands, units: units)
        }

        func beginSession() async {
            await statistics.beginSession()
        }

        func endSession() async {
            await statistics.endSession()
        }

        /// The Insulin tab's period's days, summary and hours, from the service's day cache, with the days' strings
        /// formatted here, off the main actor. Logs how long it took (the 90 d cold open is the one to time).
        /// Today is the 7 days before today and today (`InsulinStatsService.today`, Home's insulin card's days: the
        /// same usual by now), labelled as 7 d (`period`); as of the read's time (taken before the read: the service
        /// reads today up to its own clock, a moment later).
        func insulin(_ period: StatsPeriod) async throws -> InsulinResult {
            let shown = Self.insulinAndMealsShownPeriod(period)
            let period = Self.insulinAndMealsPeriod(period)
            let started = Date()
            let insulin = try await shown == .today ? insulinStatistics.today() : insulinStatistics.period(period)
            let milliseconds = Int((Date().timeIntervalSince(started) * 1000).rounded())
            debug(.service, "Statistics: insulin for \(shown == .today ? "today" : period.rawValue) in \(milliseconds) ms")
            return InsulinResult(period: period, insulin: insulin, shown: shown, asOf: started)
        }

        /// The Meals tab: the meals of the last 90 days (the fat and protein rule reads them all, D6, and the nutrient
        /// data one) computed for the period, here, off the main actor. No cache: a few rows a day.
        func meals(_ period: StatsPeriod, factor: Double) async throws -> MealsResult {
            let shown = Self.insulinAndMealsShownPeriod(period)
            let period = Self.insulinAndMealsPeriod(period)
            let calendar = Calendar.current
            let now = Date()
            let range = Self.mealsRange(period, now: now, calendar: calendar)
            let points = try await coreDataStorage.fetchMealPoints(from: range.start, to: range.end)
            return Self.mealsResult(points, period: period, shown: shown, factor: factor, now: now, calendar: calendar)
        }

        /// The Patches topic's naming from the pump sessions of the last 120 days (`PatchStatsEngine.topic`).
        func patchTopic(currentPlugin: String?) async throws -> PatchTopic? {
            let records = try await Self.pumpSessions(now: Date(), storage: coreDataStorage)
            return PatchStatsEngine.topic(PatchStatsEngine.sessions(records), currentPlugin: currentPlugin)
        }

        /// The Patches topic: every pump session of the last 120 days shown (`PatchStatsEngine.sessions`) with its
        /// numbers, computed here, off the main actor. The ended ones are kept (`patchesCache`) until a change touches
        /// them; the patch in use and the touched ones are computed again, a read of their time for each run of adjacent
        /// ones (as the Insulin tab reads its missing days). Each period is picked from them (`patchesResult`). Logs how
        /// long a computation took.
        func patches(
            _ period: StatsPeriod,
            key: PatchesCacheKey,
            deliveringPlugin: String?,
            changes: PatchChangeLog,
            currentPlugin: String?
        ) async throws -> PatchesResult {
            let coreDataStorage = self.coreDataStorage
            // the oldest schedule record the time before it is assumed from: another one computes everything again
            let windowStart = Date().addingTimeInterval(-PumpEventStore.Config.retention)
            let schedules = try await coreDataStorage.fetchBasalSchedules(from: windowStart, to: Date())
            let key = key.assuming(AssumedSchedule.oldest(schedules, after: windowStart))
            let stats = try await patchesCache.stats(
                key: key,
                deliveringPlugin: deliveringPlugin,
                changes: changes
            ) { kept in
                let now = Date()
                let records = try await Self.pumpSessions(now: now, storage: coreDataStorage)
                let sessions = PatchStatsEngine.sessions(records)
                let inUseID = PatchStatsEngine.inUse(sessions, deliveringPlugin: deliveringPlugin)?.id
                let reused = PatchStatsEngine.reusable(kept, for: sessions, inUseID: inUseID)
                let missing = sessions.indices.filter { reused[sessions[$0].id] == nil }
                var computed: [PatchStats] = []
                for run in StatsIntervals.runs(missing) {
                    let runSessions = run.map { sessions[$0] }
                    let input = try await Self.patchInput(runSessions, now: now, storage: coreDataStorage)
                    try Task.checkCancellation()
                    computed += PatchStatsEngine.stats(
                        runSessions,
                        input: input,
                        bands: key.bands,
                        allowOneMinuteLoop: key.allowOneMinuteLoop,
                        inUseID: inUseID,
                        now: now,
                        calendar: .current
                    )
                }
                let milliseconds = Int((Date().timeIntervalSince(now) * 1000).rounded())
                debug(
                    .service,
                    "Statistics: \(missing.count) of \(sessions.count) patches computed (\(reused.count) kept) in \(milliseconds) ms"
                )
                return PatchStatsEngine.assembled(sessions, reused: reused, computed: computed)
            }
            return Self.patchesResult(stats, period: period, currentPlugin: currentPlugin, now: Date(), calendar: .current)
        }

        /// The pump session records of the last 120 days (the store's retention), to an hour after `now`.
        private static func pumpSessions(now: Date, storage: CoreDataStorage) async throws -> [PumpSessionValue] {
            try await storage.fetchPumpSessions(
                from: now.addingTimeInterval(-PumpEventStore.Config.retention),
                to: now.addingTimeInterval(.hours(1))
            )
        }

        /// A period's result from the sessions' numbers (newest first): 7–90 d the sessions overlapping it, Today the
        /// patch in use and the ones before it at its age (`PatchStatsEngine.previous`).
        static func patchesResult(
            _ stats: [PatchStats],
            period: StatsPeriod,
            currentPlugin: String?,
            now: Date,
            calendar: Calendar
        ) -> PatchesResult {
            let shown = insulinAndMealsShownPeriod(period)
            let all = stats.map(\.session)
            let window = GlucoseStatsEngine.window(for: shown, now: now, end: now, calendar: calendar)
            func picked(_ sessions: [PatchSession]) -> [PatchStats] {
                let ids = Set(sessions.map(\.id))
                return stats.filter { ids.contains($0.id) }
            }
            let isToday = shown == .today
            let inUse = isToday ? stats.first(where: \.isInUse) : nil
            return PatchesResult(
                period: shown,
                window: window,
                asOf: now,
                topic: PatchStatsEngine.topic(all, currentPlugin: currentPlugin),
                sessions: isToday ? [] : picked(PatchStatsEngine.pick(all, overlapping: window)),
                inUse: inUse,
                // at its covered age: an hour out of the pump's range adds no hour to the usual only. None without a known
                // age or pump data yet (`PatchSession.isComparable`)
                previous: inUse.map { inUse in
                    guard inUse.session.isComparable else { return [] }
                    return picked(PatchStatsEngine.previous(all, before: inUse.session, age: inUse.session.wear))
                } ?? [],
                scaleWear: PatchStatsEngine.scaleWear(all),
                hasEarlier: inUse.map { inUse in
                    all.contains { $0.plugin == inUse.session.plugin && $0.activation < inUse.session.activation }
                } ?? false,
                recordingStart: all.map(\.dataStart).min()
            )
        }

        /// The rows of the sessions' time, as the Insulin tab and the glucose statistics read them: the state running
        /// into it, the events and the IOB up to an hour after it (the next temp clips one running over its end), the
        /// readings from `GlucoseStatistics.Config.lookback` before it, the loop records.
        private static func patchInput(
            _ sessions: [PatchSession],
            now: Date,
            storage coreDataStorage: CoreDataStorage
        ) async throws -> PatchInput {
            guard let start = sessions.map(\.dataStart).min(), let end = sessions.map(\.end).max() else {
                return PatchInput()
            }
            let source: InsulinDataSource = coreDataStorage
            let to = Swift.max(start, Swift.min(end.addingTimeInterval(.hours(1)), now))
            async let events = source.fetchPumpEvents(from: start, to: to)
            async let iob = source.fetchIOBPoints(
                from: start.addingTimeInterval(-(InsulinStatsEngine.iobMaximumSpan + InsulinStatsEngine.iobDuplicateWindow)),
                to: to
            )
            async let glucose = coreDataStorage.fetchGlucosePoints(
                from: start.addingTimeInterval(-GlucoseStatistics.Config.lookback),
                to: to
            )
            async let loops = HomeLoopsCoreDataSource().loopRecords(in: DateInterval(start: start, end: to), throughEnd: true)
            let runningInto = try await source.fetchPumpEventsRunningInto(start)
            let coverage = try await source.fetchCoverage(from: Swift.min(runningInto.first?.date ?? start, start), to: to)
            let schedules = try await source.fetchBasalSchedules(from: start, to: to)
            return try await PatchInput(
                insulin: InsulinInput(events: runningInto + events, coverage: coverage, schedules: schedules, iob: iob),
                glucose: glucose,
                loops: loops
            )
        }

        /// The period computed: Today and 24 h as the nearest of the computed periods (7 d: the Meals tab's Today is
        /// computed as it; the Insulin tab's is labelled with it, its days are `InsulinStatsService.today`'s), the others
        /// as they are.
        static func insulinAndMealsPeriod(_ period: StatsPeriod) -> StatsPeriod {
            Stat.StateModel.nearest(period, in: Stat.insulinAndMealsPeriods)
        }

        /// The period shown: the nearest one the tabs offer (24 h is Today).
        static func insulinAndMealsShownPeriod(_ period: StatsPeriod) -> StatsPeriod {
            Stat.StateModel.nearest(period, in: Stat.insulinAndMealsTabPeriods)
        }

        /// The meals read for a period: from the first of the last `MealStatsEngine.fatOrProteinDays` days (or the
        /// period's, when longer) to the end of today.
        static func mealsRange(_ period: StatsPeriod, now: Date, calendar: Calendar) -> DateInterval {
            let days = InsulinStatsEngine.periodDays(period, now: now, calendar: calendar)
            let today = calendar.startOfDay(for: now)
            let fatOrProteinStart = StatsClock.dayStart(MealStatsEngine.fatOrProteinDays - 1, before: today, calendar: calendar)
                ?? today
            let start = Swift.min(days.first?.start ?? today, fatOrProteinStart)
            let end = days.last?.end ?? today.addingTimeInterval(.days(1))
            return DateInterval(start: start, end: Swift.max(start, end))
        }

        /// - Parameters:
        ///   - points: `mealsRange`'s
        ///   - shown: Today, or nil for `period`
        static func mealsResult(
            _ points: [MealPoint],
            period: StatsPeriod,
            shown: StatsPeriod? = nil,
            factor: Double,
            now: Date,
            calendar: Calendar
        ) -> MealsResult {
            let meals = MealStatsEngine.period(
                period,
                points: points,
                fatOrProteinLogged: MealStatsEngine.logsFatOrProtein(points, now: now, calendar: calendar),
                factor: factor,
                now: now,
                calendar: calendar
            )
            let nutrients = NutrientStatsEngine.period(
                meals.days,
                points: points,
                now: now,
                logsNutrients: NutrientStatsEngine.logsNutrients(points, now: now, calendar: calendar)
            )
            return MealsResult(
                period: period,
                meals: meals,
                nutrients: nutrients,
                shown: shown,
                asOf: now,
                calendar: calendar
            )
        }

        private static func traceResult(
            _ trace: TraceData,
            range: TraceRange,
            bands: StatsBands
        ) -> TraceResult {
            typealias Engine = GlucoseStatsEngine
            let axis = Engine.glucoseAxis(highest: trace.points.map { Double($0.mgdl) }.max())
            return TraceResult(
                range: range,
                domain: trace.domain,
                window: trace.window,
                points: Engine.tracePoints(trace.points, axis: axis, bands: bands),
                axis: axis,
                ticks: Engine.traceTicks(in: trace.domain, endsNow: range == .last24h, calendar: .current),
                summary: trace.summary
            )
        }

        private static func traceSelector(_ days: PeriodDays, bands: StatsBands) -> [TraceSelectorItem] {
            TraceSelectorItem.items(days.days.map { GlucoseStatsEngine.traceStripDay($0, endRule: days.endRule, bands: bands) })
        }

        private static func agpResult(_ bins: [AGPBin?], summary: GlucoseSummary) -> AGPResult {
            typealias Engine = GlucoseStatsEngine
            let axis = Engine.agpAxis(bins)
            return AGPResult(bins: bins, points: Engine.agpPlotPoints(bins, axis: axis), axis: axis, summary: summary)
        }

        private static func dailyResult(_ days: PeriodDays, period: StatsPeriod, bands: StatsBands) -> DailyResult {
            DailyResult(
                summary: periodSummary(days, period: period, bands: bands),
                days: days.days.map { GlucoseStatsEngine.dailyDay($0, endRule: days.endRule, bands: bands, calendar: .current) }
            )
        }

        private static func weeklyResult(
            _ days: PeriodDays,
            period: StatsPeriod,
            bands: StatsBands,
            units: GlucoseUnits
        ) -> WeeklyResult {
            WeeklyResult(
                summary: periodSummary(days, period: period, bands: bands),
                weeks: GlucoseStatsEngine.weeks(days.days, count: period.weekCount ?? 0),
                units: units
            )
        }

        /// The period's summary: its days summed (the Daily and Weekly views').
        private static func periodSummary(_ days: PeriodDays, period: StatsPeriod, bands: StatsBands) -> GlucoseSummary {
            GlucoseStatsEngine.summary(
                days: days.days,
                window: days.window,
                endRule: days.endRule,
                period: period,
                bands: bands
            )
        }
    }
}

/// The Patches topic's sessions with their numbers, kept between reads (the Insulin tab's day cache's pattern):
/// - **Kept:** the ended sessions' numbers, by id, for one `Stat.PatchesCacheKey` (another one drops them all). A kept
///   one is used while its session is the same (`PatchStatsEngine.reusable`); the patch in use is always computed again.
/// - **Invalidation:** the insulin and glucose statistics' changes noted since the last read (`Stat.PatchChangeLog`)
///   drop the kept sessions they touch (`PatchStatsEngine.touches`: the intervals come widened by the services' reach);
///   a change without an interval, or changes the log no longer holds, drop them all.
/// - **Staleness:** every invalidation bumps `generation`; a computation stores only the sessions no invalidation since
///   its start touched, and never over a computation started after it.
/// - **Joining:** a read for what is in flight awaits it; another one cancels it (it checks after its fetches, and its
///   caller gets `CancellationError`). A read whose own task is already cancelled changes nothing.
actor PatchesCache {
    private struct Request: Equatable {
        let key: Stat.PatchesCacheKey
        let deliveringPlugin: String?
        let insulinSeq: Int
        let glucoseSeq: Int
    }

    private var key: Stat.PatchesCacheKey?
    private var kept: [String: PatchStats] = [:]
    /// the newest change of each signal applied
    private var insulinSeq = 0
    private var glucoseSeq = 0
    private var generation = 0
    /// the invalidations by generation (nil: everything), the last `Config.maxInvalidations`
    private var invalidations: [(generation: Int, interval: DateInterval?)] = []
    /// nothing computed before this generation is stored (the invalidations before it are gone)
    private var storeFloor = 0
    /// the computations started, and the newest one stored
    private var started = 0
    private var stored = 0
    private var inFlight: (request: Request, task: Task<[PatchStats], Error>)?

    private enum Config {
        static let maxInvalidations = 200
    }

    /// Every session's numbers: `compute` gets the kept ones (it reuses those that still are the sessions').
    func stats(
        key: Stat.PatchesCacheKey,
        deliveringPlugin: String?,
        changes: Stat.PatchChangeLog,
        compute: @escaping @Sendable(_ kept: [String: PatchStats]) async throws -> [PatchStats]
    ) async throws -> [PatchStats] {
        // a request superseded before it got here (its refresh cancelled) changes nothing
        if Task.isCancelled {
            throw CancellationError()
        }
        apply(key, changes)
        let request = Request(
            key: key,
            deliveringPlugin: deliveringPlugin,
            insulinSeq: changes.insulinSeq,
            glucoseSeq: changes.glucoseSeq
        )
        if let inFlight, inFlight.request == request {
            return try await inFlight.task.value
        }
        inFlight?.task.cancel()
        started += 1
        let number = started
        let asOf = generation
        let task = Task { [kept] in try await compute(kept) }
        inFlight = (request, task)
        defer {
            if inFlight?.task == task {
                inFlight = nil
            }
        }
        let stats = try await task.value
        store(stats, key: key, asOf: asOf, number: number)
        return stats
    }

    /// The kept sessions for `key` (for the tests).
    var keptIDs: Set<String> { Set(kept.keys) }

    private func apply(_ key: Stat.PatchesCacheKey, _ changes: Stat.PatchChangeLog) {
        guard key == self.key else {
            self.key = key
            invalidate(nil)
            insulinSeq = changes.insulinSeq
            glucoseSeq = changes.glucoseSeq
            return
        }
        apply(changes.insulin, upTo: changes.insulinSeq, from: &insulinSeq)
        apply(changes.glucose, upTo: changes.glucoseSeq, from: &glucoseSeq)
    }

    /// The changes after `applied` up to `newest`; when the log doesn't hold all of them, everything.
    private func apply(_ changes: [StatsChange], upTo newest: Int, from applied: inout Int) {
        guard newest > applied else { return }
        let pending = changes.filter { $0.seq > applied }
        if pending.map(\.seq) == Array(applied + 1 ... newest) {
            for change in pending {
                invalidate(change.interval)
            }
        } else {
            invalidate(nil)
        }
        applied = newest
    }

    private func invalidate(_ interval: DateInterval?) {
        generation += 1
        kept = kept.filter { !PatchStatsEngine.touches(interval, $0.value.session) }
        invalidations.append((generation, interval))
        if invalidations.count > Config.maxInvalidations {
            invalidations.removeFirst(invalidations.count - Config.maxInvalidations)
            storeFloor = invalidations.first?.generation ?? generation
        }
    }

    private func store(_ stats: [PatchStats], key: Stat.PatchesCacheKey, asOf: Int, number: Int) {
        guard key == self.key, number > stored, asOf >= storeFloor else { return }
        stored = number
        let since = invalidations.filter { $0.generation > asOf }.map(\.interval)
        // the sessions now, ended, that no invalidation since the start touched
        kept = Dictionary(
            stats.filter { stats in
                !stats.isInUse && !since.contains { PatchStatsEngine.touches($0, stats.session) }
            }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
