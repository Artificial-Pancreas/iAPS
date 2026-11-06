import CoreData
import Foundation
import UIKit

/// What the Loops card reads: Core Data in the app (`HomeLoopsCoreDataSource`), a fake in the tests.
protocol HomeLoopsSource: Sendable {
    /// the loop records started in `[start, end)`, or `[start, end]` with `throughEnd`
    func loopRecords(in range: DateInterval, throughEnd: Bool) async throws -> [HomeLoopStats.Record]
    /// how many loop records started in `[start, end)`
    func loopRecordCount(in range: DateInterval) async throws -> Int
    /// the newest loop start before the date
    func lastLoopStart(before date: Date) async throws -> Date?
    /// the times of the CGM readings in `[start, end)`, the ones the statistics count
    func readingTimes(in range: DateInterval) async throws -> [Date]
}

/// The loop numbers, off the main actor, with the complete days cached (`HomeLoopStats.Day`): the Home Loops card's (24 h,
/// read raw: a day at most), the Statistics Loop tab's (its range), and the Loops screen's days (`history`, the last 35).
/// One instance (`StorageAssembly`), so they share the cache and show the same numbers. A refresh of the days reads
/// today only, plus one count of the cached days' records (index-backed, the newest day's last slot into today too) that
/// catches a change to them nothing announces (the Settings wipe of the loop records, a loop saved late).
///
/// A day is complete, and cached, once it is `HomeLoopStats.Config.settleTime` past its end: its last slot reaches into
/// the next day (`HomeLoopStats.Config.slotLookahead`), and its loops are saved by then. The cache is keyed by the day's
/// start in the calendar of `identity` (a new calendar or time zone drops it) and the 1-minute loop setting (it thins
/// the readings and sets the gaps' cadence). A readings change drops the days it touches (a day depends on its own
/// readings, and the next day's first `slotLookahead`); the Settings wipe of the readings, a time zone change and a
/// memory warning drop everything. A day read before a change to it is never stored after it (`generation`).
actor HomeLoopsStore: LifetimeOwner {
    enum Config {
        /// a day is about 1 KB (its 48 parts, the causes and durations counted, the long gaps): 90 days of both
        /// settings with room
        static let maxCachedDays = 200
        /// the Loops screen's days: its calendar's five weeks (to the first weekday 4 weeks before this week's) and the
        /// last 30 days
        static let historyDays = 35
        /// beyond this the invalidation records are folded into `storeFloor`
        static let maxInvalidations = 400
    }

    private struct Key: Hashable {
        let dayStart: Date
        let allowOneMinuteLoop: Bool
    }

    let lifetime = Lifetime()

    private let source: HomeLoopsSource
    private var cache: [Key: HomeLoopStats.Day] = [:]
    private var identity: StatsCalendarIdentity?
    /// the calendar of `identity`: the readings changes are dates in it
    private var calendar: Calendar?
    /// bumped by every invalidation
    private var generation = 0
    /// the generation each day was last invalidated at, by its start
    private var invalidated: [Date: Int] = [:]
    /// nothing read before this generation is stored (everything was dropped at it)
    private var storeFloor = 0

    init(source: HomeLoopsSource) {
        self.source = source
    }

    /// Follows the changes that drop cached days (the app; the tests call `readingsChanged` / `dropAll`).
    nonisolated func follow(_ appCoordinator: AppCoordinator) {
        observe(appCoordinator.readingsChanged) { me, change in
            await me.readingsChanged(change)
        }
        observe(notification: UIApplication.didReceiveMemoryWarningNotification) { me in
            await me.dropAll()
        }
    }

    /// The days of the Loops screen (`LoopHistory`): oldest -> newest, today's part up to now last.
    struct History: Sendable, Equatable {
        /// from the start of the first day to now
        let window: DateInterval
        let days: [HomeLoopStats.Day]
        /// the newest loop start before the window
        let previousStart: Date?
    }

    /// The numbers for the range up to `now` (the card's, the Loop tab's); nil when something couldn't be read.
    func stats(
        _ period: StatsPeriod,
        allowOneMinuteLoop: Bool,
        now: Date,
        calendar: Calendar
    ) async -> HomeLoopStats? {
        let calendar = StatsClock.frozen(calendar)
        let window = GlucoseStatsEngine.window(for: period, now: now, end: now, calendar: calendar)
        do {
            let previousStart = try await source.lastLoopStart(before: window.start)
            guard HomeLoopStats.readsDays(period) else {
                let records = try await source.loopRecords(in: window, throughEnd: true)
                let readings = try await source.readingTimes(in: window)
                return HomeLoopStats.make(
                    period: period,
                    records: records,
                    previousStart: previousStart,
                    readings: readings,
                    allowOneMinuteLoop: allowOneMinuteLoop,
                    now: now,
                    calendar: calendar
                )
            }
            let days = try await checkedDays(of: window, allowOneMinuteLoop: allowOneMinuteLoop, calendar: calendar)
            return HomeLoopStats.assemble(
                period: period,
                window: window,
                days: days,
                buckets: [],
                previousStart: previousStart,
                calendar: calendar
            )
        } catch {
            debug(.service, "Loops: reading the loops failed: \(error)")
            return nil
        }
    }

    /// The last `count` days up to `now` (today's part last), for the Loops screen; nil when something couldn't be read.
    func history(
        days count: Int = Config.historyDays,
        allowOneMinuteLoop: Bool,
        now: Date,
        calendar: Calendar
    ) async -> History? {
        let calendar = StatsClock.frozen(calendar)
        let startOfToday = calendar.startOfDay(for: now)
        let start = StatsClock.dayStart(max(1, count) - 1, before: startOfToday, calendar: calendar) ?? startOfToday
        let window = DateInterval(start: start, end: max(start, now))
        do {
            let previousStart = try await source.lastLoopStart(before: window.start)
            let days = try await checkedDays(of: window, allowOneMinuteLoop: allowOneMinuteLoop, calendar: calendar)
            return History(window: window, days: days, previousStart: previousStart)
        } catch {
            debug(.service, "Loops: reading the loop history failed: \(error)")
            return nil
        }
    }

    // MARK: - Days

    /// The window's days (`days(of:)`), the complete ones checked against the records' count: a change to them nothing
    /// announces shows in it.
    private func checkedDays(
        of window: DateInterval,
        allowOneMinuteLoop: Bool,
        calendar: Calendar
    ) async throws -> [HomeLoopStats.Day] {
        var days = try await self.days(of: window, allowOneMinuteLoop: allowOneMinuteLoop, calendar: calendar)
        let complete = days.filter { Self.isComplete(day: $0.day, interval: $0.interval, now: window.end) }
        if let first = complete.first, let newest = complete.last {
            // the records the complete days counted: their own, and the newest one's last slot into the day after (each
            // day before's is the next one's own records)
            let end = max(newest.day.end, newest.lookaheadEnd)
            let total = try await source.loopRecordCount(in: DateInterval(start: first.day.start, end: end))
            let cachedTotal = complete.reduce(0) { $0 + $1.records } + newest.lookaheadRecords
            if total != cachedTotal {
                // typically a loop saved after the newest complete day was stored (one started before midnight, or in
                // its last slot after it): that day is read again; everything only when the days before it differ too
                let newestCount = try await source.loopRecordCount(in: DateInterval(start: newest.day.start, end: end))
                if total - newestCount == cachedTotal - newest.records - newest.lookaheadRecords {
                    drop(dayStart: newest.day.start)
                } else {
                    dropAll()
                }
                days = try await self.days(of: window, allowOneMinuteLoop: allowOneMinuteLoop, calendar: calendar)
            }
        }
        return days
    }

    /// The window's days: the complete ones from the cache, the others read, each run of them at once (with the
    /// lookahead after it: its last day's last slot); the complete days read are stored.
    private func days(
        of window: DateInterval,
        allowOneMinuteLoop: Bool,
        calendar: Calendar
    ) async throws -> [HomeLoopStats.Day] {
        adopt(calendar)
        let asOf = generation
        let segments = HomeLoopStats.segments(of: window, calendar: calendar)
        var days: [HomeLoopStats.Day?] = segments.map { segment in
            guard Self.isComplete(day: segment.day, interval: segment.interval, now: window.end) else { return nil }
            return cache[Key(dayStart: segment.day.start, allowOneMinuteLoop: allowOneMinuteLoop)]
        }

        var index = 0
        while index < segments.count {
            guard days[index] == nil else {
                index += 1
                continue
            }
            // a run of days to read
            var end = index
            while end + 1 < segments.count, days[end + 1] == nil {
                end += 1
            }
            // and the lookahead after it (the next day is cached), up to now
            let readEnd = min(
                segments[end].interval.end.addingTimeInterval(HomeLoopStats.Config.slotLookahead),
                window.end
            )
            let range = DateInterval(start: segments[index].interval.start, end: max(segments[index].interval.start, readEnd))
            // sorted once, each day a slice
            let records = try await source.loopRecords(in: range, throughEnd: readEnd == window.end)
                .sorted { $0.start < $1.start }
            let readings = try await source.readingTimes(in: range).sorted()
            let read = HomeLoopStats.days(
                segments[index ... end],
                windowEnd: window.end,
                records: records,
                readings: readings,
                allowOneMinuteLoop: allowOneMinuteLoop
            )
            for (position, day) in zip(index ... end, read) {
                days[position] = day
                if Self.isComplete(day: day.day, interval: day.interval, now: window.end) {
                    store(day, allowOneMinuteLoop: allowOneMinuteLoop, calendar: calendar, asOf: asOf)
                }
            }
            index = end + 1
        }
        return days.compactMap { $0 }
    }

    /// A whole calendar day, `HomeLoopStats.Config.settleTime` past its end: its last slot's loops are saved.
    private static func isComplete(day: DateInterval, interval: DateInterval, now: Date) -> Bool {
        interval == day && day.end.addingTimeInterval(HomeLoopStats.Config.settleTime) <= now
    }

    private func store(_ day: HomeLoopStats.Day, allowOneMinuteLoop: Bool, calendar: Calendar, asOf: Int) {
        guard StatsCalendarIdentity(calendar) == identity,
              asOf >= storeFloor,
              (invalidated[day.day.start] ?? Int.min) <= asOf
        else { return }
        cache[Key(dayStart: day.day.start, allowOneMinuteLoop: allowOneMinuteLoop)] = day
        if cache.count > Config.maxCachedDays {
            for key in cache.keys.sorted(by: { $0.dayStart < $1.dayStart }).prefix(cache.count - Config.maxCachedDays) {
                cache[key] = nil
            }
        }
    }

    // MARK: - Changes

    /// The days a readings change touched are read again (and the day before, for its last slot); the Settings wipe drops
    /// everything.
    func readingsChanged(_ change: ReadingsChange) {
        switch change {
        case .all:
            dropAll()
        case let .interval(interval, _):
            // no N-day range read yet: nothing cached, nothing being read to store (a read adopts the calendar first)
            guard let calendar else { return }
            generation += 1
            // and the day before: its last slot reaches into the first `slotLookahead` of the next day
            let starts = StatsClock.calendarDays(in: interval, calendar: calendar).map(\.start)
                + [
                    calendar.startOfDay(for: interval.end),
                    calendar.startOfDay(for: interval.start.addingTimeInterval(-HomeLoopStats.Config.slotLookahead))
                ]
            for start in starts {
                invalidate(dayStart: start)
            }
        }
    }

    /// One day read again (the newest complete day's record count differed).
    private func drop(dayStart: Date) {
        generation += 1
        invalidate(dayStart: dayStart)
    }

    private func invalidate(dayStart: Date) {
        invalidated[dayStart] = generation
        cache[Key(dayStart: dayStart, allowOneMinuteLoop: false)] = nil
        cache[Key(dayStart: dayStart, allowOneMinuteLoop: true)] = nil
        if invalidated.count > Config.maxInvalidations {
            invalidated.removeAll()
            storeFloor = generation
        }
    }

    func dropAll() {
        generation += 1
        cache.removeAll()
        invalidated.removeAll()
        storeFloor = generation
    }

    /// A new calendar or time zone drops the cache: its days are dates in the old one.
    private func adopt(_ calendar: Calendar) {
        let identity = StatsCalendarIdentity(calendar)
        if let current = self.identity, current != identity {
            dropAll()
        }
        self.identity = identity
        self.calendar = calendar
    }

    // MARK: - Tests

    /// the cached days, for the tests
    var cachedDayCount: Int { cache.count }
}

/// The loop numbers' reads from Core Data: only the attributes they need, as dictionaries (`LoopStatRecord.start` and
/// `Readings.date` are indexed). A failed record's cause is grouped here, once per distinct text (`causes`, kept across
/// the reads: the store's one source).
struct HomeLoopsCoreDataSource: HomeLoopsSource {
    private var container: NSPersistentContainer { CoreDataStack.shared.persistentContainer }
    /// the failures' texts repeat, over the reads too
    private let causes = LoopFailureCause.Memo()

    func loopRecords(in range: DateInterval, throughEnd: Bool) async throws -> [HomeLoopStats.Record] {
        let causes = self.causes
        return try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "LoopStatRecord")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["start", "loopStatus", "error", "duration"]
            request.predicate = NSPredicate(
                format: throughEnd ? "start >= %@ AND start <= %@" : "start >= %@ AND start < %@",
                range.start as NSDate,
                range.end as NSDate
            )
            return try context.fetch(request).compactMap { row -> HomeLoopStats.Record? in
                guard let start = row["start"] as? Date else { return nil }
                return HomeLoopStats.Record(
                    start: start,
                    status: row["loopStatus"] as? String,
                    error: row["error"] as? String,
                    durationMinutes: (row["duration"] as? NSNumber)?.doubleValue,
                    cause: causes.cause(error:status:)
                )
            }
        }
    }

    func loopRecordCount(in range: DateInterval) async throws -> Int {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "LoopStatRecord")
            request.predicate = NSPredicate(
                format: "start >= %@ AND start < %@",
                range.start as NSDate,
                range.end as NSDate
            )
            return try context.count(for: request)
        }
    }

    func lastLoopStart(before date: Date) async throws -> Date? {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "LoopStatRecord")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["start"]
            request.sortDescriptors = [NSSortDescriptor(key: "start", ascending: false)]
            request.predicate = NSPredicate(format: "start < %@", date as NSDate)
            request.fetchLimit = 1
            return try context.fetch(request).first?["start"] as? Date
        }
    }

    /// The statistics' readings (`CoreDataStorage.fetchGlucosePoints`'s predicate), their dates only.
    func readingTimes(in range: DateInterval) async throws -> [Date] {
        try await container.performBackgroundTask { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "Readings")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["date"]
            request.predicate = NSPredicate(
                format: "date >= %@ AND date < %@ AND glucose > 0 AND (type == nil OR type == %@)",
                range.start as NSDate,
                range.end as NSDate,
                GlucoseType.sgv.rawValue
            )
            return try context.fetch(request).compactMap { $0["date"] as? Date }
        }
    }
}
