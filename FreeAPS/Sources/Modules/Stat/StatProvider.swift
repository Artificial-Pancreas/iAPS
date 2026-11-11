import Foundation
import Swinject

extension Stat {
    final class Provider: StatProvider, Sendable {
        private let statistics: GlucoseStatistics
        private let insulinStatistics: InsulinStatsService
        private let coreDataStorage = CoreDataStorage()
        /// the Patches topic's sessions, for the key they were computed for
        private let patchesCache = PatchesCache()
        /// the CGM sessions: which CGM, and which sensor, gave the readings
        private let cgmSessions: CGMSessionStore
        /// the loop days (Good & bad days' loop row), Home's cache
        private let homeLoops: HomeLoopsStore
        /// whether Nightscout is configured: the Unknown card offers its backfill only then
        private let nightscoutManager: NightscoutManager
        /// the CGM topic's result, for the key it was computed for
        private let cgmCache = CGMCache()

        required init(resolver: Resolver) {
            statistics = resolver.resolve(GlucoseStatistics.self)!
            insulinStatistics = resolver.resolve(InsulinStatsService.self)!
            cgmSessions = resolver.resolve(CGMSessionStore.self)!
            homeLoops = resolver.resolve(HomeLoopsStore.self)!
            nightscoutManager = resolver.resolve(NightscoutManager.self)!
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

        /// Good & bad days: the complete days to yesterday scored, grouped and profiled (the day aggregates from the cache,
        /// the readings held, as the AGP's), and the factor rows from what is kept per day: the insulin days from their
        /// cache, the meals and the pump sessions in one fetch each, the loop days from Home's cache, all at once.
        /// Computed off the main actor; logs how long it took (90 d is the one to time).
        func goodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop: Bool) async -> GoodBadDaysData {
            let started = Date()
            let calendar = Calendar.current
            let count = period.calendarDayCount ?? 0
            // one `now` for every read: the glucose and the factors' days are the same across a midnight
            async let glucose = statistics.goodBadDays(count: count, bands: bands, now: started)
            var input = await goodBadDaysInput(
                count: count,
                allowOneMinuteLoop: allowOneMinuteLoop,
                now: started,
                calendar: calendar
            )
            let read = await glucose
            input.gri = read.gri
            let factors = GoodBadDaysEngine.factors(read.result, input: input, calendar: calendar)
            let milliseconds = Int((Date().timeIntervalSince(started) * 1000).rounded())
            debug(
                .service,
                "Statistics: good & bad days for \(period.rawValue), \(read.result.scored) days scored, in \(milliseconds) ms"
            )
            return GoodBadDaysData(
                period: period,
                result: read.result,
                factors: factors,
                sensorsRecordedFrom: input.sensors.flatMap(\.sessions).map(\.start).min()
            )
        }

        /// The factor rows' data of the `count` complete days to yesterday (and the day before them): each read on its
        /// own, at once; one that fails is nil (its rows unavailable), logged.
        private func goodBadDaysInput(
            count: Int,
            allowOneMinuteLoop: Bool,
            now: Date,
            calendar: Calendar
        ) async -> GoodBadDaysFactorInput {
            let days = GlucoseStatsEngine.completeDays(count: count + 1, today: now, calendar: calendar)
            guard let before = days.first, let last = days.last, days.count > 1 else { return GoodBadDaysFactorInput() }
            let today = calendar.startOfDay(for: now)
            // the meals of the period and the day before, and of the days `logsFatOrProtein` looks at
            let fatOrProteinStart = StatsClock.dayStart(MealStatsEngine.fatOrProteinDays - 1, before: today, calendar: calendar)
                ?? today
            let mealsStart = Swift.min(before.start, fatOrProteinStart)
            let storage = coreDataStorage
            let insulinStatistics = self.insulinStatistics
            let homeLoops = self.homeLoops
            let cgmSessions = self.cgmSessions
            async let mealPoints = Self.read("the carb entries") {
                try await storage.fetchMealPoints(from: mealsStart, to: Swift.max(mealsStart, now))
            }
            // the period's days and the day before (the boluses before its first day's meals), from the cache
            async let insulinDays = Self.read("the insulin") { try await insulinStatistics.days(days) }
            async let sessionRecords = Self.read("the pump sessions") { try await Self.pumpSessions(now: now, storage: storage) }
            // every CGM session (a few a month), as the CGM topic reads them: a sensor's first session can be long before
            async let cgmSessionRecords = cgmSessions.sessions(
                in: DateInterval(start: .distantPast, end: now.addingTimeInterval(.hours(1)))
            )
            // read to yesterday's end and the store's settle time (it is complete, so cached, then), not on into today
            async let loopDays = homeLoops.days(
                of: DateInterval(start: days[1].start, end: last.end),
                now: Swift.min(now, last.end.addingTimeInterval(HomeLoopStats.Config.settleTime)),
                allowOneMinuteLoop: allowOneMinuteLoop,
                calendar: calendar
            )

            var input = GoodBadDaysFactorInput()
            if let points = await mealPoints {
                input.meals = points.filter { $0.actualDate >= before.start && $0.actualDate < last.end }
                input.logsFatOrProtein = MealStatsEngine.logsFatOrProtein(points, now: now, calendar: calendar)
            }
            input.insulin = await insulinDays
            input.sessions = await sessionRecords.map { PatchStatsEngine.sessions($0) }
            let cgmRecords = await cgmSessionRecords
            let joinedRecords = await Self.read("the readings at the entered CGM sessions") {
                try await Self.sensorSessions(cgmRecords, storage: storage)
            }
            input.sensors = Self.goodBadDaysSensors(joinedRecords ?? cgmRecords)
            input.loops = await loopDays.map { days in
                Dictionary(days.map { (StatsDayKey($0.day.start, calendar), $0.slots) }, uniquingKeysWith: { first, _ in first })
            }
            if input.loops == nil {
                warning(.service, "Statistics: the loop days couldn't be read for Good & bad days")
            }
            return input
        }

        /// A read of Good & bad days' data: nil when it failed, logged.
        private static func read<Value>(_ what: String, _ body: () async throws -> Value) async -> Value? {
            do {
                return try await body()
            } catch {
                warning(.service, "Statistics: \(what) couldn't be read for Good & bad days", error: error)
                return nil
            }
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

// MARK: - The CGM topic

extension Stat.Provider {
    typealias CGMResult = Stat.CGMResult
    typealias CGMPick = Stat.CGMPick
    typealias CGMSource = Stat.CGMSource
    typealias CGMSensor = Stat.CGMSensor
    typealias CGMPickResult = Stat.CGMPickResult
    typealias CGMCacheKey = Stat.CGMCacheKey
    typealias CGMUnknownInput = Stat.CGMUnknownInput

    /// The Dexcom G7's grace period, which its expected life (`KnownPlugins.cgmExpirationByPluginIdentifier`) includes:
    /// a sensor's bar leaves it out.
    static let dexcomG7Grace: TimeInterval = .hours(12)
    /// The Dexcom G7's statistics id (`KnownPlugins.cgmIdForStatistics`).
    static let dexcomG7Id = "dexcomG7"
    /// The replay reads the readings of this long before the period: the loop's window at its first loop time, which
    /// holds the reference's lead-in too (`SmoothingReplay.replay`).
    static let replayLookback = SmoothingReplay.liveWindow

    /// The CGM topic: the period's readings and every session (`sensorSessions`), computed here, off the main actor,
    /// and kept (`cgmCache`) while the period, the generation and the sessions stay. Logs how long a computation took.
    func cgm(_ period: StatsPeriod, generation: Int) async throws -> CGMResult {
        let calendar = Calendar.current
        let now = Date()
        let window = GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar)
        let sessions = await cgmSessions.sessions(in: DateInterval(start: .distantPast, end: now.addingTimeInterval(.hours(1))))
        // the Nightscout backfill's windows; nil: Nightscout isn't configured
        let windows = await cgmSessions.backfillWindows()
        let isConfigured = await nightscoutManager.isConfigured()
        let backfillWindows = isConfigured ? windows : nil
        let key = CGMCacheKey(
            period: period,
            windowStart: window.start,
            generation: generation,
            timeZone: calendar.timeZone.identifier,
            sessions: sessions,
            backfillWindows: backfillWindows
        )
        let storage = coreDataStorage
        return try await cgmCache.result(key: key) {
            let readings = try await storage.fetchGlucosePoints(from: window.start, to: now.addingTimeInterval(1))
            let joined = try await Self.sensorSessions(sessions, storage: storage, fetched: readings)
            try Task.checkCancellation()
            // on a GCD queue: the engine's fits run in parallel (`DispatchQueue.concurrentPerform`), blocking it
            let result: CGMResult = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: Self.cgmResult(
                        readings: readings,
                        sessions: joined,
                        period: period,
                        window: DateInterval(start: window.start, end: now),
                        generation: generation,
                        backfillWindows: backfillWindows,
                        now: now,
                        calendar: calendar
                    ))
                }
            }
            let milliseconds = Int((Date().timeIntervalSince(now) * 1000).rounded())
            debug(.service, "Statistics: CGM \(period.rawValue), \(readings.count) readings in \(milliseconds) ms")
            return result
        }
    }

    /// The "Which CGM was this?" sheet's input: the last 90 days (the topic's longest period, whatever is shown), the
    /// Unknown readings among them and their probable sensors.
    func cgmUnknown() async throws -> CGMUnknownInput {
        let calendar = Calendar.current
        let now = Date()
        let window = GlucoseStatsEngine.window(for: .days90, now: now, end: now, calendar: calendar)
        let readings = try await coreDataStorage.fetchGlucosePoints(from: window.start, to: now.addingTimeInterval(1))
        let sessions = await cgmSessions.sessions(in: DateInterval(start: .distantPast, end: now.addingTimeInterval(.hours(1))))
        try Task.checkCancellation()
        return Self.cgmUnknownInput(readings: readings, sessions: sessions, window: DateInterval(start: window.start, end: now))
    }

    func enterCGMSessions(_ sessions: [CGMSessionRecord], replacing: DateInterval?) async -> Bool {
        await cgmSessions.enter(sessions, replacing: replacing)
    }

    func clearEnteredCGMSessions() async -> Bool {
        await cgmSessions.removeAllEntered()
    }

    /// The sessions as the CGM topic, Good & bad days' sensor rows and the smoothing replay take them: the entered ones
    /// an earlier answer split within one sensor joined (`CGMUnknownInference.joinedEntered`), from the readings at
    /// their boundaries (`joinWindows`: a fetch each, none without such a boundary, none for a window `fetched` holds).
    /// - Parameter fetched: readings already read, oldest -> newest (the period's): a window inside their span is
    ///   taken from them
    static func sensorSessions(
        _ sessions: [CGMSessionRecord],
        storage: CoreDataStorage,
        fetched: [GlucosePoint] = []
    ) async throws -> [CGMSessionRecord] {
        let windows = CGMUnknownInference.joinWindows(sessions)
        guard windows.isNotEmpty else { return sessions }
        var readings: [GlucosePoint] = []
        for window in windows {
            if let first = fetched.first, let last = fetched.last, first.time <= window.start, window.end <= last.time {
                let lower = fetched.partitionIndex { $0.time >= window.start }
                let upper = fetched.partitionIndex { $0.time >= window.end }
                readings += fetched[lower ..< upper]
            } else {
                readings += try await storage.fetchGlucosePoints(from: window.start, to: window.end)
            }
        }
        return CGMUnknownInference.joinedEntered(sessions, readings: readings)
    }

    /// The smoothing analysis: the readings of the pick from the loop's window before the period to now, its sessions,
    /// replayed on a GCD queue (`SmoothingReplay.replay` blocks its thread while its loop times run in parallel).
    func smoothingReplay(
        _ period: StatsPeriod,
        pick: CGMPick,
        isCancelled: @escaping @Sendable() -> Bool,
        progress: @escaping @Sendable(Double) -> Void
    ) async throws -> SmoothingReplayResult? {
        let calendar = Calendar.current
        let now = Date()
        let window = GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar)
        let from = window.start.addingTimeInterval(-Self.replayLookback)
        let readings = try await coreDataStorage.fetchGlucosePoints(from: from, to: now.addingTimeInterval(1))
        let stored = await cgmSessions.sessions(in: DateInterval(start: from, end: now.addingTimeInterval(.hours(1))))
        let sessions = try await Self.sensorSessions(stored, storage: coreDataStorage, fetched: readings)
        guard !isCancelled() else { return nil }
        let input = Self.replayInput(readings, sessions: sessions, pick: pick)
        let replayed = DateInterval(start: window.start, end: now)
        let started = Date()
        let result: SmoothingReplayResult? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SmoothingReplay.replay(
                    readings: input.readings,
                    sessions: input.sessions,
                    period: replayed,
                    now: now,
                    isCancelled: isCancelled,
                    progress: progress
                ))
            }
        }
        let milliseconds = Int((Date().timeIntervalSince(started) * 1000).rounded())
        debug(
            .service,
            "Statistics: smoothing replay \(period.rawValue), \(input.readings.count) readings, " +
                (result == nil ? "cancelled" : "\(result?.loopTimes ?? 0) loop times") + " in \(milliseconds) ms"
        )
        return result
    }

    // MARK: The result, pure

    /// The sheet's input from the 90 days' readings and every session: the readings no recorded session covers (an
    /// entered one is what the sheet changes), their probable sensors, the CGM entered for each.
    static func cgmUnknownInput(
        readings: [GlucosePoint],
        sessions: [CGMSessionRecord],
        window: DateInterval
    ) -> CGMUnknownInput {
        let recorded = sessions.filter { $0.source == .recorded }
        let entered = sessions.filter { $0.source == .entered }
        let cleaned = CGMStatsEngine.cleaned(
            readings,
            in: DateInterval(start: window.start, end: .distantFuture),
            now: window.end
        )
        let unknown = CGMSessionAttribution.attribute(cleaned, to: recorded).unknown
        let choices = CGMChoice.choices(recorded: recorded)
        let sensors = CGMUnknownInference.sensors(
            unknown,
            allReadings: cleaned.map(\.time),
            choices: choices,
            readFrom: window.start
        )
        return CGMUnknownInput(
            window: window,
            sensors: sensors,
            choices: choices,
            unknownTimes: unknown.map(\.time),
            recorded: recorded,
            entered: CGMUnknownInference.entered(sensors, sessions: entered),
            enteredSessions: entered.filter { $0.end.map { $0 > window.start } ?? true }.count
        )
    }

    /// The pick of a session without a statistics id but with a name (AppGroup before its source is known): its plugin
    /// after this, so it isn't any CGM's id.
    static let pluginPickPrefix = "plugin:"

    /// The pick a session's readings are: its CGM's id; without one its plugin (named by the session), Unknown when it
    /// has no name either.
    static func pick(of session: CGMSessionRecord) -> CGMPick {
        if let cgmId = session.cgmId {
            return .cgm(cgmId)
        }
        return session.name.isEmpty ? .unknown : .cgm(pluginPickPrefix + session.plugin)
    }

    /// Where a session's readings begin, as the sensor boundaries take it: its sensor's start, but never before the
    /// session (a sensor inserted ahead, or a CGM switched to, gives the readings from the session's start; those
    /// before it are the previous session's).
    static func readingsStart(_ session: CGMSessionRecord) -> Date {
        Swift.max(session.sensorStartOrStart, session.start)
    }

    /// The sensor boundaries of the sessions (`sensorBoundary(bySession:)`), ascending.
    static func sensorBoundaries(_ sessions: [CGMSessionRecord]) -> [Date] {
        sensorBoundary(bySession: sessions).values.sorted()
    }

    /// Each session's `readingsStart`, when a sensor began there (its own start at the session's) or a session came
    /// before it (a new sensor, a CGM switched to); judged against every session (a sensor started ahead of a switch to
    /// it follows the other CGM's session). Not the first session of a sensor already running when the recording
    /// began, nor one opened without a known start after none: nothing changed in the readings there.
    static func sensorBoundary(bySession sessions: [CGMSessionRecord]) -> [UUID: Date] {
        let sorted = CGMSessionRules.ordered(sessions)
        let tolerance = BloodGlucose.sessionTolerance
        var boundaries: [UUID: Date] = [:]
        for index in sorted.indices {
            let session = sorted[index]
            let sensorStartedThen = session.sensorStart.map {
                $0 > session.start || abs($0.timeIntervalSince(session.start)) <= tolerance
            } ?? false
            // not after another session of the same sensor (an entered one up to its recording)
            let followsAnother = index > 0 &&
                (sorted[index - 1].end.map { session.start.timeIntervalSince($0) <= tolerance } ?? false) &&
                !isSameSensor(sorted[index - 1], session)
            if sensorStartedThen || followsAnother {
                boundaries[session.id] = readingsStart(session)
            }
        }
        return boundaries
    }

    /// Good & bad days' CGM sensors: the sessions of each sensor together (`mergedSensors`, the CGM topic's: a CGM
    /// switched away and back is the same sensor), its start the sensor's own (`sensorStart`, the same within the
    /// group; a session without one is a group of its own, not identified). Not the readings' boundary
    /// (`sensorBoundary`): a switch to a sensor started the evening before counts its wear day from then, and is no change.
    static func goodBadDaysSensors(_ sessions: [CGMSessionRecord]) -> [GoodBadDaysSensor] {
        mergedSensors(sessions).map { group in
            GoodBadDaysSensor(start: group[0].sensorStart, sessions: group.map(\.interval))
        }
    }

    /// The same CGM, and sensor starts within the readings' session tolerance.
    static func isSameSensor(_ one: CGMSessionRecord, _ other: CGMSessionRecord) -> Bool {
        guard let cgmId = one.cgmId, cgmId == other.cgmId, let a = one.sensorStart, let b = other.sensorStart else {
            return false
        }
        return abs(a.timeIntervalSince(b)) <= BloodGlucose.sessionTolerance
    }

    /// The sensor starts the engine takes for a CGM's sessions (`CGMStatsEngine.stats`): at each sensor's first
    /// session's boundary only (a CGM switched away and back is the same sensor, its readings and days go on).
    /// - Parameters:
    ///   - boundaries: `sensorBoundary(bySession:)` of every session
    ///   - firsts: the first session of each sensor (`mergedSensors` of every session)
    static func sensorStarts(_ sessions: [CGMSessionRecord], boundaries: [UUID: Date], firsts: Set<UUID>) -> [Date] {
        sessions.filter { firsts.contains($0.id) }.compactMap { boundaries[$0.id] }.sorted()
    }

    /// The sessions of one sensor together: the same CGM, and a sensor start within the readings' session tolerance of
    /// the group's first one (a CGM switched away and back: a second row for the same sensor, `CGMSessionRules`; a
    /// computed start moves by seconds); a session without either alone. Each group by start, the groups by their first
    /// start.
    static func mergedSensors(_ sessions: [CGMSessionRecord]) -> [[CGMSessionRecord]] {
        var groups: [[CGMSessionRecord]] = []
        for session in CGMSessionRules.ordered(sessions) {
            guard let sensorStart = session.sensorStart, session.cgmId != nil else {
                groups.append([session])
                continue
            }
            let existing = groups.firstIndex { group in
                group[0].cgmId == session.cgmId &&
                    group[0].sensorStart.map { abs($0.timeIntervalSince(sensorStart)) <= BloodGlucose.sessionTolerance } ?? false
            }
            if let existing {
                groups[existing].append(session)
            } else {
                groups.append([session])
            }
        }
        return groups
    }

    /// The readings and the sessions the replay of a pick takes: a CGM its sessions' readings; Unknown the readings no
    /// session names.
    static func replayInput(
        _ readings: [GlucosePoint],
        sessions: [CGMSessionRecord],
        pick: CGMPick
    ) -> (readings: [GlucosePoint], sessions: [CGMSessionRecord]) {
        let attribution = CGMSessionAttribution.attribute(readings, to: sessions)
        let picked = attribution.bySession.filter { self.pick(of: $0.session) == pick }
        let own = picked.flatMap(\.readings) + (pick == .unknown ? attribution.unknown : [])
        return (own.sorted { $0.time < $1.time }, picked.map(\.session))
    }

    /// The CGM topic's result from the period's readings and every recorded session.
    /// - Parameters:
    ///   - readings: the period's (`window`), any order
    ///   - window: the period's `[start, now]`
    ///   - backfillWindows: the windows the Nightscout backfill ran over (`CGMSessionStore.backfillWindows`); nil:
    ///     Nightscout isn't configured
    static func cgmResult(
        readings: [GlucosePoint],
        sessions: [CGMSessionRecord],
        period: StatsPeriod,
        window: DateInterval,
        generation: Int,
        backfillWindows: [DateInterval]? = nil,
        now: Date,
        calendar: Calendar
    ) -> CGMResult {
        let attribution = CGMSessionAttribution.attribute(readings, to: sessions)
        let unknownName = NSLocalizedString("Unknown", comment: "Statistics CGM: the readings from before the CGM was recorded")
        // the entered sessions the sheet changes: in its 90 days (`cgmUnknown`)
        let enteredFrom = GlucoseStatsEngine.window(for: .days90, now: now, end: now, calendar: calendar).start

        // the readings and the sessions of each CGM, Unknown the remainder
        var readingsByPick: [CGMPick: [GlucosePoint]] = [.unknown: attribution.unknown]
        var sessionsByPick: [CGMPick: [CGMSessionRecord]] = [:]
        for part in attribution.bySession {
            let pick = self.pick(of: part.session)
            readingsByPick[pick, default: []] += part.readings
            sessionsByPick[pick, default: []].append(part.session)
        }
        let picked = readingsByPick.mapValues { CGMStatsEngine.cleaned($0, in: window, now: now) }
        // the named CGMs by their first reading, Unknown last
        func firstTime(_ pick: CGMPick) -> Date {
            picked[pick]?.first?.time ?? .distantFuture
        }
        let named: [CGMPick] = picked.keys
            .filter { pick in pick != .unknown && !(picked[pick] ?? []).isEmpty }
            .sorted { firstTime($0) < firstTime($1) }
        var cgms: [CGMSource] = named.map { pick in
            CGMSource(pick: pick, name: sessionsByPick[pick]?.last?.name ?? unknownName)
        }
        if !(picked[.unknown] ?? []).isEmpty {
            cgms.append(CGMSource(pick: .unknown, name: unknownName))
        }

        let sortedSessions = CGMSessionRules.ordered(sessions)
        let boundaryBySession = sensorBoundary(bySession: sessions)
        let groups = mergedSensors(sessions)
        let firsts = Set(groups.map { $0[0].id })
        // the readings of each session, by id
        let readingsBySession = Dictionary(
            attribution.bySession.map { ($0.session.id, $0.readings) },
            uniquingKeysWith: { first, _ in first }
        )

        func pickResult(_ pick: CGMPick) -> CGMPickResult {
            let points = picked[pick] ?? []
            let starts: [Date] = pick == .unknown ? [] : sensorStarts(
                sessionsByPick[pick] ?? [],
                boundaries: boundaryBySession,
                firsts: firsts
            )
            let (stats, residuals) = CGMStatsEngine.analysed(
                readings: points,
                sensorStarts: starts,
                period: window,
                now: now
            )
            // the sensors with readings on each sensor day (`CGMStatsEngine.sensorDay`), the readings and the starts
            // walked together, each day of a sensor added once
            var sensorsOnDay: [Int: Set<Date>] = [:]
            var next = 0
            var index = 0
            var added: (day: Int, start: Int)?
            while index < points.count {
                defer { index += 1 }
                let time = points[index].time
                while next < starts.count, starts[next] <= time {
                    next += 1
                }
                guard next > 0 else { continue }
                let day = Int(time.timeIntervalSince(starts[next - 1]) / .days(1)) + 1
                guard added.map({ $0.day != day || $0.start != next - 1 }) ?? true else { continue }
                added = (day, next - 1)
                sensorsOnDay[day, default: []].insert(starts[next - 1])
            }
            let sensors: [CGMSensor] = pick == .unknown ? [] : groups.filter { group in
                self.pick(of: group[0]) == pick && group.contains { session in
                    session.start < window.end && (session.end.map { $0 > window.start } ?? true)
                }
            }.map { group in
                sensor(
                    group,
                    readingsBySession: readingsBySession,
                    residuals: residuals,
                    window: window,
                    now: now
                )
            }
            return CGMPickResult(
                stats: stats,
                sensorsBySensorDay: sensorsOnDay.mapValues(\.count),
                sensors: sensors.sorted { $0.start > $1.start }
            )
        }

        var picks: [CGMPick: CGMPickResult] = [:]
        for source in cgms {
            picks[source.pick] = pickResult(source.pick)
        }

        return CGMResult(
            period: period,
            window: window,
            asOf: now,
            generation: generation,
            cgms: cgms,
            picks: picks,
            recordingStart: sortedSessions.first { $0.source == .recorded }?.start,
            enteredSessions: sessions.filter { session in
                session.source == .entered && session.end.map { $0 > enteredFrom } ?? true
            }.count,
            hasEnteredSessions: sessions.contains { $0.source == .entered },
            backfilledReadings: attribution.bySession.filter { $0.session.source == .backfilled }
                .reduce(0) { count, part in count + part.readings.filter { $0.time >= window.start }.count },
            // an Unknown reading the backfill could still name: in its days, outside every window it ran over
            backfillCanName: backfillWindows.map { windows in
                let from = Swift.max(now.addingTimeInterval(-NightscoutCGMBackfill.maxAge), window.start)
                return attribution.unknown.contains { point in
                    point.time >= from && !windows.contains { $0.contains(point.time) }
                }
            } ?? false
        )
    }

    /// A sensor's row: its sessions' readings' noise in the period (their own fits: those of its CGM's segments it
    /// shares, `CGMStatsEngine.noise(…reusing:)`).
    /// - Parameters:
    ///   - readingsBySession: every session's readings
    ///   - residuals: its CGM's (`CGMStatsEngine.analysed`)
    private static func sensor(
        _ group: [CGMSessionRecord],
        readingsBySession: [UUID: [GlucosePoint]],
        residuals: CGMSegmentResiduals,
        window: DateInterval,
        now: Date
    ) -> CGMSensor {
        let first = group[0]
        let last = group[group.count - 1]
        let points = group.flatMap { readingsBySession[$0.id] ?? [] }
        let life = last.expectedLife ?? first.expectedLife
        return CGMSensor(
            id: first.id,
            pick: pick(of: first),
            name: last.name,
            start: first.start,
            sensorStart: first.sensorStart,
            end: last.end,
            expectedLife: life,
            grace: life != nil && first.cgmId == dexcomG7Id ? dexcomG7Grace : 0,
            noise: CGMStatsEngine.noise(readings: points, period: window, now: now, reusing: residuals),
            isEntered: first.source == .entered,
            isBackfilled: first.source == .backfilled
        )
    }
}

/// The CGM topic's result, kept for its key (`Stat.CGMCacheKey`): another key computes it again. A read for what is in
/// flight awaits it; one for another key cancels it.
actor CGMCache {
    private var key: Stat.CGMCacheKey?
    private var result: Stat.CGMResult?
    private var inFlight: (key: Stat.CGMCacheKey, task: Task<Stat.CGMResult, Error>)?

    func result(
        key: Stat.CGMCacheKey,
        compute: @escaping @Sendable() async throws -> Stat.CGMResult
    ) async throws -> Stat.CGMResult {
        if let result, self.key == key {
            return result
        }
        if let inFlight, inFlight.key == key {
            return try await inFlight.task.value
        }
        inFlight?.task.cancel()
        let task = Task { try await compute() }
        inFlight = (key, task)
        defer {
            if inFlight?.task == task {
                inFlight = nil
            }
        }
        let value = try await task.value
        if inFlight?.task == task {
            self.key = key
            result = value
        }
        return value
    }
}
