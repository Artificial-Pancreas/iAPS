import Foundation

enum Stat {
    enum Config {}

    /// What the Day tab shows: the 24 hours, today, or a day before it (one of the selector's days,
    /// `selectorPeriod`). Today is its own case, so it follows midnight.
    enum TraceDay: Hashable, Sendable {
        case last24h
        case today
        /// the start of a day before today
        case day(Date)

        /// The days the selector offers: the last 90, today included (`GlucoseStatistics.days`, from the day cache).
        static let selectorPeriod: StatsPeriod = .days90

        /// A calendar day picked (the selector, the stepper): today, or after it, is `.today`; a day before it is kept
        /// from its start.
        /// - Parameter today: the start of today
        static func of(_ day: Date, today: Date, calendar: Calendar) -> TraceDay {
            let start = calendar.startOfDay(for: day)
            return start < today ? .day(start) : .today
        }

        /// The selector's items for its days, oldest -> newest (the last one today): the past days, today, and the
        /// 24 hours at the trailing end (it isn't a calendar day).
        static func items(days: [Date]) -> [TraceDay] {
            days.indices.map { index -> TraceDay in index == days.count - 1 ? .today : .day(days[index]) } + [.last24h]
        }

        /// What is shown for it: a past day kept inside the selector's days (midnight moves its first day on: the
        /// nearest of them, `GlucoseStatsEngine.shownDay`), today when that is the nearest.
        func shown(today: Date, calendar: Calendar) -> TraceDay {
            guard case let .day(day) = self else { return self }
            return GlucoseStatsEngine.shownDay(day, period: Self.selectorPeriod, today: today, calendar: calendar)
                .map { TraceDay.day($0) } ?? .today
        }

        /// The range computed for it; today is the day of `requestedAt` (so the schedule sees the day computed).
        func range(requestedAt: Date, calendar: Calendar) -> TraceRange {
            switch self {
            case .last24h: return .last24h
            case .today: return .day(calendar.startOfDay(for: requestedAt))
            case let .day(day): return .day(day)
            }
        }
    }

    /// What the statistics depend on from the settings: the bands (low/high and units) and the HbA1c unit.
    struct StatsSettings: Equatable, Sendable {
        let bands: StatsBands
        let units: GlucoseUnits
        let hbA1cUnit: HbA1cUnit

        init(_ settings: FreeAPSSettings) {
            bands = StatsBands(low: settings.low, high: settings.high, units: settings.units)
            units = settings.units
            hbA1cUnit = HbA1cUnit.resolve(units: settings.units, override: settings.overrideHbA1cUnit)
        }
    }

    /// What the Day tab (the Trace) shows, computed off the main actor (`Provider.trace`): the readings ready to plot,
    /// the axes and the summary. Never empty: a day without readings shows the chart with "No readings" and dashes
    /// (the screen shows "no data" only when none of the selector's days has a reading, `TraceSelectorItem.nothingToShow`).
    struct TraceResult: Equatable, Sendable {
        typealias Point = TracePoint

        let range: TraceRange
        /// the x axis: the whole calendar day, or the 24 hours before E
        let domain: DateInterval
        /// `[start, E)`
        let window: DateInterval
        /// the readings starting inside the window, oldest -> newest
        let points: [Point]
        /// mg/dL (`GlucoseStatsEngine.glucoseAxis`)
        let axis: ClosedRange<Int>
        /// the local 00/06/12/18 inside the domain (`GlucoseStatsEngine.traceTicks`)
        let ticks: [Date]
        let summary: GlucoseSummary
    }

    /// An item of the Day tab's selector, formatted off the main actor (`Provider.traceSelector`, like
    /// `StatsDayLabel`): a day of the last 90 (the past ones, today) or the 24 hours.
    struct TraceSelectorItem: Equatable, Sendable, Identifiable {
        let pick: TraceDay
        /// "Mon", "Today"; nil for the 24 hours
        let caption: String?
        /// "27"; "24 h"
        let number: String
        /// "Mon 27 Oct", "Today", "Last 24 hours"
        let title: String
        /// the in-range bar; 0 for a day without readings, nil for the 24 hours (not a calendar day: no bar)
        let inRangeFraction: Double?
        /// a reading starts in it; false for the 24 hours
        let hasReadings: Bool

        var id: TraceDay { pick }

        /// The selector: its days oldest -> newest (the last one today), then the 24 hours; none without days.
        static func items(_ days: [TraceStripDay]) -> [TraceSelectorItem] {
            guard days.isNotEmpty else { return [] }
            let todayTitle = NSLocalizedString("Today", comment: "")
            let last24hTitle = NSLocalizedString("Last 24 hours", comment: "")
            let picks = TraceDay.items(days: days.map(\.start))
            return zip(days, picks).map { day, pick -> TraceSelectorItem in
                let isToday = pick == .today
                return TraceSelectorItem(
                    pick: pick,
                    caption: isToday ? todayTitle : day.start.formatted(.dateTime.weekday(.abbreviated)),
                    number: day.start.formatted(.dateTime.day()),
                    title: isToday ? todayTitle : Trace.dayTitle(day.start),
                    inRangeFraction: day.hasReadings ? day.inRangeFraction : 0,
                    hasReadings: day.hasReadings
                )
            } + [
                TraceSelectorItem(
                    pick: .last24h,
                    caption: nil,
                    number: NSLocalizedString("24 h", comment: "Statistics period"),
                    title: last24hTitle,
                    inRangeFraction: nil,
                    hasReadings: false
                )
            ]
        }

        /// Nothing to show on the Day tab: the selector is in and none of its days has a reading (a day without
        /// readings among others shows the chart with "No readings").
        static func nothingToShow(_ items: [TraceSelectorItem]) -> Bool {
            items.isNotEmpty && items.allSatisfy { !$0.hasReadings }
        }
    }

    /// The Day tab's usual day (`Provider.usualDay`): the AGP of the last N days ending today (the AGP tab's window for
    /// that N), the same for every day stepped through, and that window's summary (its days with data, its coverage:
    /// drawn or not, limited or not).
    struct UsualDayResult: Equatable, Sendable {
        /// one of `StatsPeriod.usualDayPeriods`
        let period: StatsPeriod
        /// `GlucoseStatsEngine.agpBinMinutes` each, from 00:00; nil for a bin without data (pooled with its neighbours)
        let bins: [AGPBin?]
        let summary: GlucoseSummary
    }

    /// What the AGP shows, computed off the main actor (`Provider.agp`): the profile ready to plot, its axis, and the
    /// period's summary (the key numbers, the same as the Overview's).
    struct AGPResult: Equatable, Sendable {
        typealias Point = AGPPlotPoint

        /// `GlucoseStatsEngine.agpBinMinutes` each, from 00:00; nil for a bin without data (pooled with its neighbours)
        let bins: [AGPBin?]
        /// the chart's points (`GlucoseStatsEngine.agpPlotPoints`)
        let points: [Point]
        /// mg/dL (`GlucoseStatsEngine.glucoseAxis` of the highest p95)
        let axis: ClosedRange<Int>
        /// the period's, as the Overview's
        let summary: GlucoseSummary

        /// Nothing in the period: no covered time and no bin with data.
        var isEmpty: Bool {
            summary.isEmpty && bins.allSatisfy { $0 == nil }
        }
    }

    /// What the Daily view shows, computed off the main actor (`Provider.daily`): the period's days ready to draw, and
    /// the period's summary (the Overview's).
    struct DailyResult: Equatable, Sendable {
        typealias Day = DailyDay

        /// the period's, as the Overview's
        let summary: GlucoseSummary
        /// oldest -> newest, the last one today (`GlucoseStatsEngine.dailyDay`)
        let days: [Day]
        /// by day
        let labels: [StatsDayLabel]

        init(summary: GlucoseSummary, days: [Day], calendar: Calendar = .current) {
            self.summary = summary
            self.days = days
            labels = days.map { StatsDayLabel($0.day.start, calendar: calendar) }
        }

        /// Nothing in the period: no covered time and no day with a reading. Covered only by a span running in from
        /// before the period (the Overview shows its numbers), it isn't empty: the chart without bars, "No readings".
        var isEmpty: Bool {
            summary.isEmpty && days.allSatisfy { !$0.hasReadings }
        }
    }

    /// What By hour shows, computed off the main actor (`Provider.hourOfDay`): the 24 clock hours ready to draw, the
    /// peaks of "When it happens", and the period's summary (the Overview's).
    struct HourOfDayResult: Equatable, Sendable {
        typealias Hour = HourOfDayHour

        /// 0...23, by the local clock (`GlucoseStatsEngine.hourOfDayHour`)
        let hours: [Hour]
        /// below, in range, above: those whose peak share isn't 0 (`GlucoseStatsEngine.peakHours`)
        let peaks: [PeakHour]
        /// by hour: "08:00–09:00", "8:00 – 9:00 AM", the hour as the locale shows a time interval (`AGP.clockInterval`),
        /// formatted with the result (off the main actor)
        let labels: [String]
        /// the period's, as the Overview's
        let summary: GlucoseSummary

        /// - Parameter buckets: `GlucoseStatistics.hourOfDay`'s, for the period of `summary`
        init(buckets: [HourBucket], summary: GlucoseSummary, bands: StatsBands) {
            let buckets = buckets.sorted { $0.hour < $1.hour }
            let hours = buckets.map { GlucoseStatsEngine.hourOfDayHour($0, bands: bands) }
            self.hours = hours
            peaks = GlucoseStatsEngine.peakHours(buckets, bands: bands)
            labels = hours.map { AGP.clockInterval(from: $0.hour * 60, to: ($0.hour + 1) * 60) }
            self.summary = summary
        }

        /// Nothing in the period: no covered time and no hour with data.
        var isEmpty: Bool {
            summary.isEmpty && hours.allSatisfy { !$0.hasData }
        }
    }

    /// What Weekly shows, computed off the main actor (`Provider.weekly`): the period's weeks against the period (each
    /// week's in range and mean as shown, and their Δ), and the period's summary (the Overview's).
    struct WeeklyResult: Equatable, Sendable {
        typealias Week = WeeklyWeek

        /// A week's strings, formatted with the result (off the main actor).
        struct Label: Equatable, Sendable {
            /// "24–30 Oct", "29 Sep – 5 Oct": its days, as the locale shows a date interval
            let title: String
            /// "24 Oct": its first day, on the charts' axis
            let start: String

            init(_ week: Week) {
                title = (week.days.start ..< Swift.max(week.lastDay, week.days.start))
                    .formatted(.interval.day().month(.abbreviated))
                start = week.days.start.formatted(.dateTime.day().month(.abbreviated))
            }
        }

        /// the period's, as the Overview's
        let summary: GlucoseSummary
        /// the units the means and their Δ are shown in
        let units: GlucoseUnits
        /// the period's mean as shown (`GlucoseStatsEngine.shownMean`); nil without data
        let averageMean: Decimal?
        /// oldest -> newest, the last one includes today (`GlucoseStatsEngine.weeklyWeek`)
        let weeks: [Week]
        /// by week
        let labels: [Label]

        /// - Parameter weeks: `GlucoseStatsEngine.weeks` of the days of the period of `summary`
        init(summary: GlucoseSummary, weeks: [WeekAggregate], units: GlucoseUnits) {
            self.summary = summary
            self.units = units
            averageMean = summary.mean.map { GlucoseStatsEngine.shownMean($0, units: units) }
            let shown = weeks.map { GlucoseStatsEngine.weeklyWeek($0, average: summary, units: units) }
            self.weeks = shown
            labels = shown.map { Label($0) }
        }

        /// Nothing in the period: no covered time and no week with a reading. Covered only by a span running in from
        /// before the period (the Overview shows its numbers), it isn't empty: the charts without bars, every week
        /// "no data".
        var isEmpty: Bool {
            summary.isEmpty && weeks.allSatisfy { !$0.hasData }
        }
    }

    /// What By weekday shows, computed off the main actor (`Provider.weekday`): the period's weekdays (whole weeks to
    /// yesterday), each one's hours and 3-hour blocks with the same hours on the other six days (the usual), and the
    /// workdays against the weekend; every one of them by column, in the order shown (`GlucoseStatsEngine.weekdayOrder`:
    /// the workdays, then the weekend).
    struct WeekdayResult: Equatable, Sendable {
        /// one of `StatsPeriod.weekdayPeriods`
        let period: StatsPeriod
        /// the days of each weekday the period holds
        let weeks: Int
        /// the first day's start to the end of the last, yesterday
        let window: DateInterval
        /// the start of the last day (yesterday)
        let lastDay: Date
        /// the columns: `Calendar` weekdays (1 Sunday … 7 Saturday), the workdays, then the weekend
        let order: [Int]
        /// the weekend's columns, at the end of `order`; 0 without a weekend
        let weekendCount: Int
        /// by column
        let weekdays: [WeekdayPool]
        /// by column, then by clock hour (24) / by 3-hour block (8)
        let hours: [[WeekdayPool]]
        let blocks: [[WeekdayPool]]
        /// by column, then by hour / block: the same hours on the other six weekdays
        let usualHours: [[WeekdayPool]]
        let usualBlocks: [[WeekdayPool]]
        /// the workdays' and the weekend's columns pooled; the weekend nil without one
        let workdays: WeekdayPool
        let weekend: WeekdayPool?
        /// by column: the period's days of the weekday a reading starts in
        let daysWithData: [Int]
        /// the oldest reading of the period
        let firstReading: Date?
        /// the start of the first day with readings, when that is after the period's first day and the store has no
        /// reading before the period: the recording began inside it
        let recordedSince: Date?

        /// - Parameter pooled: `GlucoseStatsEngine.weekdayHours`', with the columns' order by its calendar
        init(_ pooled: WeekdayHours, period: StatsPeriod) {
            typealias Engine = GlucoseStatsEngine
            self.period = period
            weeks = period.weekCount ?? (pooled.days.count / 7)
            let window = pooled.window ?? DateInterval(start: Date(), duration: 0)
            self.window = window
            lastDay = pooled.days.last?.start ?? window.start
            order = pooled.order
            weekendCount = pooled.weekend.count
            let columns = pooled.order.map { $0 - 1 }

            func sum(_ cells: [WeekdayCell]) -> WeekdayTally {
                cells.reduce(WeekdayTally()) { $0 + $1.tally }
            }
            weekdays = columns.map { Engine.weekdayPool(sum(pooled.hours[$0]), days: pooled.daysWithData[$0], hoursPerCell: nil) }
            func cells(_ grid: [[WeekdayCell]], hoursPerCell: Int) -> [[WeekdayPool]] {
                columns.map { column in
                    grid[column].map { Engine.weekdayPool($0.tally, days: $0.days, hoursPerCell: hoursPerCell) }
                }
            }
            func usual(_ grid: [[WeekdayCell]]) -> [[WeekdayPool]] {
                columns.map { column in
                    grid[column].indices.map { row in
                        let others = (0 ..< 7).filter { $0 != column }.map { grid[$0][row] }
                        return Engine.weekdayPool(sum(others), days: others.reduce(0) { $0 + $1.days }, hoursPerCell: nil)
                    }
                }
            }
            hours = cells(pooled.hours, hoursPerCell: 1)
            blocks = cells(pooled.blocks, hoursPerCell: Engine.weekdayBlockHours)
            usualHours = usual(pooled.hours)
            usualBlocks = usual(pooled.blocks)
            func group(_ weekdays: [Int]) -> WeekdayPool {
                let indices = weekdays.map { $0 - 1 }
                return Engine.weekdayPool(
                    sum(indices.flatMap { pooled.hours[$0] }),
                    days: indices.reduce(0) { $0 + pooled.daysWithData[$1] },
                    hoursPerCell: nil
                )
            }
            workdays = group(pooled.order.dropLast(pooled.weekend.count).map { $0 })
            weekend = pooled.weekend.isEmpty ? nil : group(pooled.weekend)
            daysWithData = columns.map { pooled.daysWithData[$0] }
            firstReading = pooled.firstReading
            recordedSince = pooled.hasReadingsBefore ? nil : pooled.firstDayWithData.flatMap { $0 > window.start ? $0 : nil }
        }

        /// One day weighs a lot (the Days row, the mark): the recording began inside the period (`recordedSince`), or
        /// some weekday has readings on at most half the period's weeks. A day without readings here and there isn't.
        var isLimited: Bool {
            guard !isEmpty else { return false }
            return recordedSince != nil || (daysWithData.min() ?? 0) * 2 <= weeks
        }

        /// Nothing in the period: no covered time.
        var isEmpty: Bool {
            weekdays.allSatisfy { !$0.hasData }
        }
    }

    /// What Good & bad days shows, computed off the main actor (`Provider.goodBadDays`): the period's complete days
    /// scored by GRI, the best and the worst third with their profiles and glucose rows (`GoodBadDaysEngine.result`),
    /// and their factor rows (`GoodBadDaysEngine.factors`).
    struct GoodBadDaysData: Equatable, Sendable {
        /// one of `StatsPeriod.usualDayPeriods`
        let period: StatsPeriod
        let result: GoodBadDaysResult
        /// in `GoodBadFactor`'s order; none without both thirds shown
        var factors: [GoodBadDaysFactorRow] = []
        /// the first CGM session's start (recorded, entered or backfilled): sensors started before weren't recorded
        var sensorsRecordedFrom: Date?

        /// no day of the period has enough CGM data to be scored
        var isEmpty: Bool { result.scored == 0 }
    }

    /// The periods the Insulin and Meals tabs compute (`InsulinStatsEngine.periodDays`: the engines don't special-case
    /// Today and 24 h). The Meals tab's Today is computed as 7 d; the Insulin tab's is labelled 7 d, its usual by now over
    /// the 7 days before today (`InsulinStatsService.today`: the 7 d period is 6 and today).
    static let insulinAndMealsPeriods: [StatsPeriod] = [.days7, .days14, .days30, .days90]

    /// The periods the Insulin and Meals tabs offer: Today first (a view of its own, with 7 d: see
    /// `insulinAndMealsPeriods`), then the N-day ones. 24 h is shown as Today (the nearest), the weekly periods as 30
    /// and 90 d.
    static let insulinAndMealsTabPeriods: [StatsPeriod] = [.today] + insulinAndMealsPeriods

    /// What the Insulin tab shows, computed off the main actor (`Provider.insulin`): the period's days, the summary
    /// (rule a) and the hours (`InsulinStatsService.period`; on Today `InsulinStatsService.today`: the 7 days before
    /// today and today), with the days' strings.
    struct InsulinResult: Equatable, Sendable {
        /// the period computed: one of `insulinAndMealsPeriods`; Today's 7 d, its label ("Usual by 14:35 · 7 d"), its
        /// days the 7 before today and today
        let period: StatsPeriod
        /// the period shown: Today, or `period`
        let shown: StatsPeriod
        /// the read's time: Today is as of it ("Usual by 14:35")
        let asOf: Date
        let insulin: InsulinPeriod
        /// by day, formatted with the result (off the main actor)
        let labels: [StatsDayLabel]

        /// - Parameter shown: Today, or nil for `period`
        init(
            period: StatsPeriod,
            insulin: InsulinPeriod,
            shown: StatsPeriod? = nil,
            asOf: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.period = period
            self.shown = shown ?? period
            self.asOf = asOf
            self.insulin = insulin
            labels = insulin.days.map { StatsDayLabel($0.day.start, calendar: calendar) }
        }

        /// no covered time and no bolus or temp in the period: "No pump data in this period"
        var isEmpty: Bool { insulin.summary.isEmpty }
    }

    /// What the Meals tab shows, computed off the main actor (`Provider.meals`): `MealStatsEngine.period` of the
    /// period's meals and their fiber, vitamins and minerals (`NutrientStatsEngine.period`), with the days' strings.
    struct MealsResult: Equatable, Sendable {
        /// the period computed: one of `insulinAndMealsPeriods` (Today is 7 d)
        let period: StatsPeriod
        /// the period shown: Today, or `period`
        let shown: StatsPeriod
        /// the read's time (the engines' `now`): Today is as of it
        let asOf: Date
        let meals: MealPeriod
        /// the same days'
        let nutrients: NutrientPeriod
        /// by day, formatted with the result (off the main actor)
        let labels: [StatsDayLabel]

        /// - Parameter shown: Today, or nil for `period`
        init(
            period: StatsPeriod,
            meals: MealPeriod,
            nutrients: NutrientPeriod,
            shown: StatsPeriod? = nil,
            asOf: Date = Date(),
            calendar: Calendar = .current
        ) {
            self.period = period
            self.shown = shown ?? period
            self.asOf = asOf
            self.meals = meals
            self.nutrients = nutrients
            labels = meals.days.map { StatsDayLabel($0.day.start, calendar: calendar) }
        }

        /// no entry in the period, today included: "No carb entries in this period"
        var isEmpty: Bool { meals.summary.isEmpty }
    }

    /// What the Patches topic shows, computed off the main actor (`Provider.patches`): 7–90 d the sessions overlapping
    /// the period, each whole; Today the patch in use and the ones before it at its age (`PatchStatsEngine.previous`).
    struct PatchesResult: Equatable, Sendable {
        /// the period shown: Today, or one of `insulinAndMealsPeriods`
        let period: StatsPeriod
        /// the period's `[start, now]`
        let window: DateInterval
        /// the read's time
        let asOf: Date
        /// the naming (patches or pods); nil without sessions in the last 120 days
        let topic: PatchTopic?
        /// 7–90 d: newest first; empty on Today
        let sessions: [PatchStats]
        /// Today: the patch in use; nil without one ("No patch in use")
        let inUse: PatchStats?
        /// Today: the patches of its plugin before it, recorded whole and worn at least as long as it so far, newest
        /// first (`PatchStatsEngine.previous`); their numbers up to its age are summed from their hours
        let previous: [PatchStats]
        /// the longest wear that sets the wear bars' scale (`PatchStatsEngine.scaleWear`), the same on every period
        let scaleWear: TimeInterval
        /// Today: some patch of its plugin came before it (`previous` can still be empty: none reached its age)
        var hasEarlier = false
        /// the recording's start: the oldest data start of every session read (not only the period's), what "activated
        /// before the recording began" is said against; nil without sessions
        var recordingStart: Date?

        /// 7–90 d without a session overlapping the period; Today is never empty ("No patch in use")
        var isEmpty: Bool { period != .today && sessions.isEmpty }

        /// Today: the patch in use's age, its time since the activation (its day, its bar)
        var age: TimeInterval? { inUse.map { asOf.timeIntervalSince($0.session.activation) } }

        /// Today: the age it is compared at, its covered age (to its coverage's end): an hour out of the pump's range
        /// adds no hour to the usual only (`PatchStatsEngine.previous` is filtered by it too)
        var comparisonAge: TimeInterval? { inUse?.session.wear }
    }

    /// What every kept session of the Patches topic depends on (`PatchesCache`): another one drops them all.
    struct PatchesCacheKey: Equatable, Sendable {
        let bands: StatsBands
        let allowOneMinuteLoop: Bool
        /// the screen's own invalidations: coming back from the background (or up again), a settings change, a
        /// midnight passed on screen
        let generation: Int
        let timeZone: String
        /// the oldest basal schedule record the time before it is assumed from (`AssumedSchedule.oldest`), set
        /// by the provider: a Nightscout schedule import that changes it computes everything again
        var assumedSchedule: AssumedSchedule?

        func assuming(_ schedule: AssumedSchedule?) -> PatchesCacheKey {
            var key = self
            key.assumedSchedule = schedule
            return key
        }
    }

    /// The insulin and glucose statistics' changes seen while Statistics is up (`insulinStatsChanged`,
    /// `glucoseStatsChanged`): the newest seq seen of each and the recent changes, so the Patches topic's kept sessions
    /// drop only those a change touched (`PatchesCache`).
    struct PatchChangeLog: Equatable, Sendable {
        /// the recent changes kept of each; a cache further behind drops everything
        static let capacity = 500

        /// the newest seen
        private(set) var insulinSeq: Int
        private(set) var glucoseSeq: Int
        /// oldest -> newest
        private(set) var insulin: [StatsChange] = []
        private(set) var glucose: [StatsChange] = []

        /// - Parameters: the signals' seq when Statistics came up: the changes after them are noted
        init(insulinSeq: Int, glucoseSeq: Int) {
            self.insulinSeq = insulinSeq
            self.glucoseSeq = glucoseSeq
        }

        mutating func noteInsulin(_ change: StatsChange) {
            guard change.seq > insulinSeq else { return }
            insulinSeq = change.seq
            insulin = Array((insulin + [change]).suffix(Self.capacity))
        }

        mutating func noteGlucose(_ change: StatsChange) {
            guard change.seq > glucoseSeq else { return }
            glucoseSeq = change.seq
            glucose = Array((glucose + [change]).suffix(Self.capacity))
        }
    }

    /// The periods the CGM topic offers (`StatsTab.cgmOverview` …): no Today, its figures need hours of readings.
    static let cgmPeriods: [StatsPeriod] = [.days7, .days14, .days30, .days90]

    /// A pick of the CGM topic's picker: one CGM (its statistics id, `CGMSessionRecord.cgmId`), or the readings no
    /// session with an id covers. Readings of different CGMs are never pooled.
    enum CGMPick: Hashable, Sendable {
        case cgm(String)
        case unknown
    }

    /// A CGM with readings in the period: what the picker lists.
    struct CGMSource: Equatable, Sendable, Identifiable {
        let pick: CGMPick
        /// the manager's title of its newest session ("Dexcom G7"); "Unknown" for the readings no session names
        let name: String

        var id: CGMPick { pick }
    }

    /// A sensor of the Sensors view: a CGM session, or several of the same CGM and sensor start (a CGM switched away
    /// and back), merged (`Provider.mergedSensors`).
    struct CGMSensor: Equatable, Sendable, Identifiable {
        /// its first session's
        let id: UUID
        let pick: CGMPick
        let name: String
        /// the session's start (its first's)
        let start: Date
        /// the sensor's own start, nil when the CGM gives none (the session's start is used then)
        let sensorStart: Date?
        /// its last session's end; nil while it is in use
        let end: Date?
        /// from the sensor start, its grace included; nil when unknown
        let expectedLife: TimeInterval?
        /// the part of `expectedLife` that is grace (`Provider.dexcomG7Grace`): its bar leaves it out
        let grace: TimeInterval
        /// its readings' noise in the period
        let noise: CGMNoise?
        /// its first session is one the user entered (`CGMSessionSource.entered`): its start inferred from the readings
        var isEntered = false
        /// its first session was named from Nightscout (`CGMSessionSource.backfilled`)
        var isBackfilled = false

        /// where its length counts from: its own start, else the session's
        var lifeStart: Date { sensorStart ?? start }
        var isInUse: Bool { end == nil }
    }

    /// What one pick shows (`CGMResult.picks`).
    struct CGMPickResult: Equatable, Sendable {
        let stats: CGMStats
        /// by sensor day: the sensors with readings on it
        let sensorsBySensorDay: [Int: Int]
        /// newest first
        let sensors: [CGMSensor]
    }

    /// What the CGM topic shows, computed off the main actor (`Provider.cgm`): the period's readings run through
    /// `CGMStatsEngine.stats` once per CGM (attributed to the CGM sessions, `CGMSessionAttribution`), the sensors of
    /// the sessions overlapping the period.
    struct CGMResult: Equatable, Sendable {
        let period: StatsPeriod
        /// the period's `[start, now]`
        let window: DateInterval
        let asOf: Date
        /// the data generation it was read for (`CGMCacheKey.generation`): the smoothing results are kept by it
        let generation: Int
        /// the CGMs with readings in the period: the named ones by their first reading, Unknown last
        let cgms: [CGMSource]
        /// each of `cgms`
        let picks: [CGMPick: CGMPickResult]
        /// the oldest recorded session's start: the readings before it are Unknown, unless entered; nil without one
        let recordingStart: Date?
        /// the entered sessions' parts (`CGMSessionSource.entered`, after a recorded session clipped them) in the
        /// sheet's 90 days (`Provider.cgmUnknown`): "3 periods entered by you", Change
        var enteredSessions = 0
        /// any entered session, older ones too: Clear
        var hasEnteredSessions = false
        /// the period's readings a backfilled session names (`CGMSessionSource.backfilled`): "Nightscout named …"
        var backfilledReadings = 0
        /// Nightscout is configured and an Unknown reading lies in the backfill's days outside every window it ran
        /// over: the Unknown card offers the backfill
        var backfillCanName = false

        /// no reading in the period: "No CGM data in this period"
        var isEmpty: Bool { cgms.isEmpty }

        /// The pick shown: the one asked for while the period has it, else the default (`defaultPick`); nil without
        /// readings.
        func shown(_ pick: CGMPick?) -> CGMPick? {
            if let pick, cgms.contains(where: { $0.pick == pick }) {
                return pick
            }
            return defaultPick
        }

        /// The named CGM with the newest reading in the period; Unknown only without a named one.
        var defaultPick: CGMPick? {
            let named = cgms.filter { $0.pick != .unknown }
            let newest = named.max { first, second in
                (picks[first.pick]?.stats.span?.end ?? .distantPast) < (picks[second.pick]?.stats.span?.end ?? .distantPast)
            }
            return newest?.pick ?? cgms.first?.pick
        }
    }

    /// What the "Which CGM was this?" sheet starts from (`Provider.cgmUnknown`): the Unknown readings of the CGM topic's
    /// longest period, the readings no recorded session covers (an entered one doesn't count: the answer is changed).
    struct CGMUnknownInput: Equatable, Sendable {
        /// the 90 days' `[start, now]`
        let window: DateInterval
        /// oldest first (`CGMUnknownInference.sensors`)
        let sensors: [CGMProbableSensor]
        /// the recorded sessions' CGMs first, then the ones iAPS knows (`CGMChoice.choices`)
        let choices: [CGMChoice]
        /// the Unknown readings' times, ascending
        let unknownTimes: [Date]
        /// the recorded sessions (`CGMUnknownInference.sessions`: a run starting with a recorded sensor is that sensor)
        let recorded: [CGMSessionRecord]
        /// by sensor: the CGM of the entered session holding its first reading
        let entered: [Date: String]
        /// the entered sessions' parts in the 90 days
        let enteredSessions: Int

        /// the Unknown readings' `[first, last]`; nil without them
        var span: DateInterval? {
            guard let first = unknownTimes.first, let last = unknownTimes.last else { return nil }
            return DateInterval(start: first, end: last)
        }

        /// The time an answer covers, the entered sessions in it replaced: the Unknown readings' span, to just after
        /// the last.
        var replaced: DateInterval? {
            span.map { DateInterval(start: $0.start, end: $0.end.addingTimeInterval(1)) }
        }
    }

    /// What a CGM result depends on (`CGMCache`): another one computes it again.
    struct CGMCacheKey: Equatable, Sendable {
        let period: StatsPeriod
        /// the period's first day: midnight moves it on
        let windowStart: Date
        /// the screen's: bumped by every readings change seen (`glucoseStatsChanged`), coming back from the background
        /// or up again
        let generation: Int
        let timeZone: String
        /// every recorded session: one that changed (a new sensor, an end) computes it again
        let sessions: [CGMSessionRecord]
        /// the Nightscout backfill's windows (nil: Nightscout isn't configured): the Unknown card's offer
        var backfillWindows: [DateInterval]? = nil
    }

    /// What a view shows: the previous content stays (dimmed) while the new one is computed.
    enum ViewContent<Value: Equatable>: Equatable {
        case loading(previous: Value?)
        case loaded(Value)
        case empty
        /// the data couldn't be read and nothing of the request's is shown (the Insulin and Meals tabs; a read that
        /// fails with the request's previous content on screen keeps it, `keepingPrevious`)
        case failed

        var value: Value? {
            switch self {
            case let .loading(previous): return previous
            case let .loaded(value): return value
            case .empty,
                 .failed: return nil
            }
        }

        /// After a failed read: the content on screen stays when it is the request's own (`isCurrent` of it: a live
        /// update's, or the same period's dimmed while it was read again), otherwise nothing of another period is shown
        /// as the request's: `failed`. An empty period stays empty.
        func keepingPrevious(isCurrent: (Value) -> Bool) -> ViewContent<Value> {
            switch self {
            case let .loaded(value):
                return .loaded(value)
            case let .loading(previous?) where isCurrent(previous):
                return .loaded(previous)
            case .empty:
                return .empty
            case .failed,
                 .loading:
                return .failed
            }
        }

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }
}

/// A day's strings in the day-by-day charts (Days, Insulin, Meals, Nutrients), formatted with the result (off the main
/// actor): up to 90 of them on every refresh.
struct StatsDayLabel: Equatable, Sendable {
    /// "Mon 27 Oct" (`Trace.dayTitle`)
    let title: String
    /// "27"
    let number: String
    /// the weekday's initial ("M"), the month on the 1st ("Nov")
    let caption: String

    init(_ day: Date, calendar: Calendar) {
        title = Stat.Trace.dayTitle(day)
        number = day.formatted(.dateTime.day())
        caption = calendar.component(.day, from: day) == 1
            ? day.formatted(.dateTime.month(.abbreviated))
            : day.formatted(.dateTime.weekday(.narrow))
    }
}

/// A card Statistics opens scrolled to (`Stat.RootView`, `Screen.statistics`).
enum StatsFocus: Hashable, Sendable {
    /// the Insulin topic's Negative IOB card (Home's On board card, its Negative IOB row)
    case negativeIOB
}

/// The topics of Statistics, in the title menu (`StatsViewMenu`): Glucose (its eight views), Insulin, Patches (offered
/// while the last 120 days hold a pod or patch), Meals and CGM (its three views).
enum StatsTopic: String, CaseIterable, Identifiable, Sendable, Hashable {
    case glucose
    case insulin
    case patches
    case meals
    case cgm

    var id: String { rawValue }

    /// The views the topic offers, in the menu's order: Glucose's eight; Insulin, Patches and Meals one each; CGM's three.
    var views: [StatsTab] {
        switch self {
        case .glucose: return StatsTab.allCases.filter(\.isGlucose)
        case .insulin: return [.insulin]
        case .patches: return [.patches]
        case .meals: return [.meals]
        case .cgm: return StatsTab.allCases.filter(\.isCGM)
        }
    }
}

/// The views of Statistics: the Glucose topic's, in the menu's order, then the Insulin, Patches and Meals topics' (one
/// each), then the CGM topic's.
enum StatsTab: String, CaseIterable, Identifiable, Sendable, Hashable {
    case overview
    /// "Day": one day's readings (`TraceView`)
    case trace
    case agp
    /// "Good & bad days": the days scored by GRI, two groups of them compared (`GoodBadDaysView`)
    case goodBadDays
    /// "In range by day": time in ranges day by day (`DailyView`)
    case daily
    /// "By hour": time in ranges by the hour of the day (`HourOfDayView`)
    case hourOfDay
    /// "By weekday": the weekdays, and each one's hours (`WeekdayView`)
    case weekday
    /// each of the last 13 weeks against them (`WeeklyView`)
    case weekly
    /// the insulin per day (basal, SMB, bolus) and by hour (`InsulinView`)
    case insulin
    /// pod by pod, patch by patch, and by wear day (`PatchesView`)
    case patches
    /// the carbs per day and by time of day (`MealsView`)
    case meals
    /// the CGM's coverage, gaps, noise, reversals, jitter and rate of change (`CGMView`)
    case cgmOverview
    /// sensor by sensor, and the noise by sensor day (`CGMView`)
    case cgmSensors
    /// what the loop saw under each smoothing setting, replayed on Analyse (`CGMSmoothingView`)
    case cgmSmoothing

    var id: String { rawValue }

    /// computed from the glucose readings (and the bands)
    var isGlucose: Bool {
        topic == .glucose
    }

    /// a view of the CGM topic: one result for all three (`Stat.CGMResult`)
    var isCGM: Bool {
        topic == .cgm
    }

    /// its numbers depend on the bands (the settings): the glucose views, and Patches (each one's time in range)
    var usesBands: Bool {
        isGlucose || self == .patches
    }

    /// what it shows depends on the settings: the bands' views, and the CGM topic's (in the glucose unit)
    var usesSettings: Bool {
        usesBands || isCGM
    }

    var topic: StatsTopic {
        switch self {
        case .agp,
             .daily,
             .goodBadDays,
             .hourOfDay,
             .overview,
             .trace,
             .weekday,
             .weekly: return .glucose
        case .insulin: return .insulin
        case .patches: return .patches
        case .meals: return .meals
        case .cgmOverview,
             .cgmSensors,
             .cgmSmoothing: return .cgm
        }
    }

    /// The periods the view offers; none on the Day tab (its day selector replaces them: it neither uses nor changes
    /// the preferred period). Weekly has one, its 13 weeks, and "In range by day" one, its 90 days (the chart
    /// scrolls through them): no period control, and they neither use nor change the preferred period either (it is
    /// always the nearest one offered). By weekday has whole weeks, a period of its own (`Stat.StateModel.weekdayPeriod`):
    /// it neither uses nor changes the preferred one. Good & bad days has 14, 30 and 90 days (a group needs 5 days), a
    /// period of its own too (`Stat.StateModel.goodBadDaysPeriod`).
    var validPeriods: [StatsPeriod] {
        switch self {
        case .overview: return StatsPeriod.homeRanges
        case .trace: return []
        case .agp,
             .hourOfDay: return [.days7, .days14, .days30, .days90]
        case .daily: return [.days90]
        case .weekly: return [.weeks13]
        case .weekday: return StatsPeriod.weekdayPeriods
        case .goodBadDays: return StatsPeriod.usualDayPeriods
        case .insulin,
             .meals,
             .patches: return Stat.insulinAndMealsTabPeriods
        case .cgmOverview,
             .cgmSensors,
             .cgmSmoothing: return Stat.cgmPeriods
        }
    }

    /// a period control: more than one period to pick from (not the Day tab, not Weekly, not "In range by day")
    var hasPeriodControl: Bool {
        validPeriods.count > 1
    }
}

protocol StatProvider: Provider {
    func summary(_ period: StatsPeriod, bands: StatsBands) async -> GlucoseSummary
    func trace(_ range: TraceRange, bands: StatsBands) async -> Stat.TraceResult
    /// the Day tab's selector: the last 90 days (`Stat.TraceDay.selectorPeriod`, from the day cache) and the 24 hours
    func traceSelector(bands: StatsBands) async -> [Stat.TraceSelectorItem]
    /// the Day tab's usual day: the AGP of the last N days ending today, loaded on its own (stepping days doesn't
    /// recompute it)
    func usualDay(_ period: StatsPeriod, bands: StatsBands) async -> Stat.UsualDayResult
    func agp(_ period: StatsPeriod, bands: StatsBands) async -> Stat.AGPResult
    func daily(_ period: StatsPeriod, bands: StatsBands) async -> Stat.DailyResult
    func hourOfDay(_ period: StatsPeriod, bands: StatsBands) async -> Stat.HourOfDayResult
    /// By weekday: one of `StatsPeriod.weekdayPeriods`, the whole weeks to yesterday
    func weekday(_ period: StatsPeriod, bands: StatsBands) async -> Stat.WeekdayResult
    /// Good & bad days: one of `StatsPeriod.usualDayPeriods`, the complete days to yesterday; `allowOneMinuteLoop` sets
    /// the loop row's slots. A failed insulin, meals, sessions or loops read marks only their rows unavailable
    func goodBadDays(_ period: StatsPeriod, bands: StatsBands, allowOneMinuteLoop: Bool) async -> Stat.GoodBadDaysData
    /// the means and their Δ are shown, and so computed, in `units` (in mmol/L the difference of the displayed values)
    func weekly(_ period: StatsPeriod, bands: StatsBands, units: GlucoseUnits) async -> Stat.WeeklyResult
    /// the Insulin tab: Today (and 24 h, shown as Today) is computed as 7 d. Throws when the insulin data couldn't be
    /// read (never shown as "no pump data")
    func insulin(_ period: StatsPeriod) async throws -> Stat.InsulinResult
    /// the Meals tab: Today (and 24 h, shown as Today) is computed as 7 d; `factor` is the current
    /// `individualAdjustmentFactor` (the carb equivalents). Throws when the meals couldn't be read
    func meals(_ period: StatsPeriod, factor: Double) async throws -> Stat.MealsResult
    /// The Patches topic's naming, nil without a session in the last 120 days (the topic isn't offered). Throws when
    /// the pump sessions couldn't be read
    func patchTopic(currentPlugin: String?) async throws -> PatchTopic?
    /// the Patches topic: Today (and 24 h, shown as Today) is the patch in use against the ones before it at its age.
    /// The ended sessions are kept for `key`, each until a change in `changes` touches it; `deliveringPlugin` is the
    /// current pump's plugin while it has an active delivery unit (`KnownPlugins.hasActiveDeliveryUnit`): its open
    /// session is the one in use. Throws when the data couldn't be read
    func patches(
        _ period: StatsPeriod,
        key: Stat.PatchesCacheKey,
        deliveringPlugin: String?,
        changes: Stat.PatchChangeLog,
        currentPlugin: String?
    ) async throws -> Stat.PatchesResult
    /// the CGM topic: every reading of the period, per CGM and all together, and the sensors. Kept for the period,
    /// the generation and the sessions (`CGMCache`). Throws when the readings couldn't be read (a failed sessions read is
    /// none: every reading Unknown)
    func cgm(_ period: StatsPeriod, generation: Int) async throws -> Stat.CGMResult
    /// The Unknown readings of the last 90 days, their probable sensors and the CGMs to name them by (the "Which CGM
    /// was this?" sheet). Throws when the readings couldn't be read
    func cgmUnknown() async throws -> Stat.CGMUnknownInput
    /// The user's answer: entered sessions, replacing the entered ones in `replacing` (`CGMSessionStore.enter`).
    /// Returns whether it was saved
    func enterCGMSessions(_ sessions: [CGMSessionRecord], replacing: DateInterval?) async -> Bool
    /// Every entered session goes (`CGMSessionStore.removeAllEntered`). Returns whether it succeeded
    func clearEnteredCGMSessions() async -> Bool
    /// The smoothing analysis of a pick's readings over the period (`SmoothingReplay.replay`), on a GCD queue (it blocks
    /// its thread). nil when cancelled; `progress` is called from its threads (hop to the main actor asynchronously).
    /// Throws when the readings couldn't be read
    func smoothingReplay(
        _ period: StatsPeriod,
        pick: Stat.CGMPick,
        isCancelled: @escaping @Sendable() -> Bool,
        progress: @escaping @Sendable(Double) -> Void
    ) async throws -> SmoothingReplayResult?
    func beginSession() async
    func endSession() async
}
