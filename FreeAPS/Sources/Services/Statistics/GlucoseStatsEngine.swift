import Foundation

/// The glucose statistics, as pure functions: no Core Data, no `Date()`, no global calendar
/// (`now` and `calendar` are always parameters). Values are mg/dL integers throughout.
enum GlucoseStatsEngine {
    /// How many of the preceding distances define a reading's cadence.
    static let cadenceWindow = 10
    /// A median distance up to this is a 1-minute sensor. Above it, a 5-minute one: two interleaved 5-minute streams
    /// (120-180 s apart) must not snap to 1 minute.
    static let oneMinuteMedianLimit: TimeInterval = 90
    /// A distance counts in a reading's cadence only when its earlier reading is at most this long before it, so the
    /// weights depend only on the readings shortly before (a sensor switch across a gap isn't weighed with the old
    /// cadence, and a day weighs the same whatever the read starts at). The service reads
    /// `GlucoseStatistics.Config.lookback` (1 h) before every window: this, plus the longest span that can run into the
    /// window (1.5 x 5 min, from a reading before its start), has to fit in it.
    static let cadenceHorizon: TimeInterval = .minutes(50)

    // MARK: - Readings

    /// Sorted by (date, glucose), non-positive values dropped. Of readings with exactly the same timestamp (the concurrent
    /// Nightscout-import saves) the lowest glucose is kept: the fetch order of equal dates isn't stable, so "the first
    /// fetched" wouldn't be deterministic, and the (date, glucose) order makes the kept one the lowest.
    static func clean(_ points: [GlucosePoint]) -> [GlucosePoint] {
        let sorted = points
            .filter { $0.mgdl > 0 }
            .sorted { ($0.time, $0.mgdl) < ($1.time, $1.mgdl) }
        var result: [GlucosePoint] = []
        result.reserveCapacity(sorted.count)
        for point in sorted where point.time != result.last?.time {
            result.append(point)
        }
        return result
    }

    /// The sensor's cadence at a reading, from the distances before it: 1 minute when their median is at most 90 s,
    /// otherwise (and without any) 5 minutes. `weigh` passes the last `cadenceWindow` distances within `cadenceHorizon`.
    static func cadence(previousDeltas deltas: [TimeInterval]) -> TimeInterval {
        cadence(sortedDeltas: deltas.sorted())
    }

    /// `cadence(previousDeltas:)` of distances already sorted ascending.
    private static func cadence(sortedDeltas sorted: [TimeInterval]) -> TimeInterval {
        guard sorted.isNotEmpty else { return .minutes(5) }
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return median <= oneMinuteMedianLimit ? .minutes(1) : .minutes(5)
    }

    /// Each reading covers the time up to the next one, or one cadence when the next one is more than
    /// 1.5 cadences away (the rest of a gap isn't covered). The newest reading covers one cadence.
    /// - Parameter sorted: oldest -> newest, as `clean` returns them
    static func weigh(_ sorted: [GlucosePoint]) -> [WeightedPoint] {
        var result: [WeightedPoint] = []
        result.reserveCapacity(sorted.count)
        // the positive distances before the reading, with the time of their earlier reading
        var recent = CadenceWindow(capacity: cadenceWindow)

        for (index, point) in sorted.enumerated() {
            recent.drop(before: point.time.addingTimeInterval(-cadenceHorizon))
            let expected = recent.cadence
            let span: TimeInterval
            if index + 1 < sorted.count {
                let delta = sorted[index + 1].time.timeIntervalSince(point.time)
                span = delta <= expected * GapDetection.Config.tolerance ? Swift.max(delta, 0) : expected
                if delta > 0 {
                    recent.append(from: point.time, delta: delta)
                }
            } else {
                span = expected
            }
            result.append(WeightedPoint(time: point.time, mgdl: point.mgdl, span: span))
        }
        return result
    }

    /// `weigh`'s last `capacity` distances, oldest first, with their earlier reading's time, and the same distances
    /// sorted: the cadence of every reading without an allocation per reading (both buffers are allocated once).
    private struct CadenceWindow {
        /// a ring, `count` long from `head`
        private var froms: [Date]
        private var deltas: [TimeInterval]
        private var head = 0
        private var count = 0
        /// the `count` distances, ascending
        private var sorted: [TimeInterval] = []

        init(capacity: Int) {
            let capacity = Swift.max(capacity, 1)
            froms = Array(repeating: .distantPast, count: capacity)
            deltas = Array(repeating: 0, count: capacity)
            sorted.reserveCapacity(capacity)
        }

        var cadence: TimeInterval {
            GlucoseStatsEngine.cadence(sortedDeltas: sorted)
        }

        /// Drops the distances whose earlier reading is before the date.
        mutating func drop(before date: Date) {
            while count > 0, froms[head] < date {
                removeOldest()
            }
        }

        /// Adds a distance; the oldest one goes when the window is full.
        mutating func append(from: Date, delta: TimeInterval) {
            if count == froms.count {
                removeOldest()
            }
            let index = (head + count) % froms.count
            froms[index] = from
            deltas[index] = delta
            count += 1
            var position = sorted.count
            while position > 0, sorted[position - 1] > delta {
                position -= 1
            }
            sorted.insert(delta, at: position)
        }

        private mutating func removeOldest() {
            if let index = sorted.firstIndex(of: deltas[head]) {
                sorted.remove(at: index)
            }
            head = (head + 1) % froms.count
            count -= 1
        }
    }

    // MARK: - Windows

    /// The end E of every window: the newest reading's end while the data is current (no more than 1.5 cadences old),
    /// otherwise `now` floored to the minute, but never before the newest reading's end (a 1-minute reading can end
    /// after the floored minute, and E must not move backwards when the data turns stalled). Never after the end of today.
    /// - Parameter w: everything fetched up to the end of today, oldest -> newest (the newest one's span is its cadence)
    static func effectiveEnd(_ w: [WeightedPoint], now: Date, calendar: Calendar) -> Date {
        effectiveEndRule(w, now: now, calendar: calendar).end
    }

    /// E (`effectiveEnd`), and the rule that gave it: current up to the newest reading's time + 1.5 of its span
    /// (its cadence, the newest reading's span), stalled after that or without readings.
    static func effectiveEndRule(_ w: [WeightedPoint], now: Date, calendar: Calendar) -> (end: Date, rule: StatsEndRule) {
        let end: Date
        let rule: StatsEndRule
        if let newest = w.last, now.timeIntervalSince(newest.time) <= newest.span * GapDetection.Config.tolerance {
            end = newest.end
            rule = .current(stallsAt: newest.time.addingTimeInterval(newest.span * GapDetection.Config.tolerance))
        } else {
            let minute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            end = Swift.max(minute, w.last?.end ?? minute)
            rule = .stalled
        }
        return (Swift.min(end, StatsClock.endOfDay(now, calendar: calendar)), rule)
    }

    /// `[start, end)`; an N-day period starts N-1 days before today, 24 h is the 24 hours before `end`.
    /// The start is never after the end (Today just after midnight, with E still yesterday, is empty).
    static func window(for period: StatsPeriod, now: Date, end: Date, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let start: Date
        switch period {
        case .today:
            start = startOfToday
        case .last24h:
            start = end.addingTimeInterval(-TimeInterval.hours(24))
        case .days7,
             .days14,
             .days30,
             .days90,
             .weeks4,
             .weeks5,
             .weeks8,
             .weeks13:
            let days = period.calendarDayCount ?? 1
            start = StatsClock.dayStart(days - 1, before: startOfToday, calendar: calendar) ?? startOfToday
        }
        return DateInterval(start: start, end: Swift.max(start, end))
    }

    /// The calendar days touching the window, each clipped to it, oldest -> newest.
    static func days(in window: DateInterval, calendar: Calendar) -> [DateInterval] {
        StatsClock.calendarDays(in: window, calendar: calendar)
            .map { StatsIntervals.clipped($0, to: window) ?? DateInterval(start: $0.start, duration: 0) }
    }

    /// The days of a period, oldest -> newest, each clipped to the window (`window(for: period, ...)`).
    /// An N-day or weekly period has exactly `calendarDayCount` days, ending with today; just after midnight, while E is
    /// still before the start of today, today is an empty, zero-length day at its start (and still one of the N).
    /// Today, 24 h and rolling windows (`period` nil) get the days touching the window.
    static func days(for period: StatsPeriod?, window: DateInterval, calendar: Calendar) -> [DateInterval] {
        guard let count = period?.calendarDayCount else { return days(in: window, calendar: calendar) }
        let first = calendar.startOfDay(for: window.start)
        return (0 ..< count).map { offset -> DateInterval in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: first).map { calendar.startOfDay(for: $0) }
                ?? first.addingTimeInterval(.days(offset))
            let day = DateInterval(start: dayStart, end: StatsClock.endOfDay(dayStart, calendar: calendar))
            return StatsIntervals.clipped(day, to: window) ?? DateInterval(start: dayStart, duration: 0)
        }
    }

    // MARK: - Aggregation

    /// The spans clipped to the window; a reading counts (readingCount, first/last, min/max) when it starts inside.
    static func histogram(_ w: [WeightedPoint], clippedTo window: DateInterval) -> GlucoseHistogram {
        var histogram = GlucoseHistogram()
        var index = firstIndex(in: w, endingAfter: window.start)
        while index < w.count, w[index].time < window.end {
            let point = w[index]
            histogram.add(
                point,
                seconds: StatsIntervals.overlap(from: point.time, to: point.end, in: window),
                startsInside: point.time >= window.start
            )
            index += 1
        }
        return histogram
    }

    /// One histogram per day; a span across midnight is split between the two days.
    static func dayAggregates(_ w: [WeightedPoint], days: [DateInterval]) -> [DayAggregate] {
        days.map { DayAggregate(day: $0, histogram: histogram(w, clippedTo: $0)) }
    }

    /// Calendar days and days with data, "n of N". N is the period's `calendarDayCount` (today included, even while it
    /// is still empty just after midnight); Today and 24 h always count as one day; a rolling window (`period` nil)
    /// counts the days given. A day has data when a reading starts in it: the previous evening's span running past
    /// midnight doesn't count.
    /// - Parameter days: the aggregates of `days(for: period, ...)`
    static func dayCounts(_ period: StatsPeriod?, days: [DayAggregate]) -> (calendarDays: Int, daysWithData: Int) {
        let withData = days.filter { $0.histogram.readingCount > 0 }.count
        switch period {
        case .last24h?,
             .today?:
            return (1, Swift.min(withData, 1))
        case let period?:
            return (period.calendarDayCount ?? days.count, withData)
        case nil:
            return (days.count, withData)
        }
    }

    /// The summary of a window from its days, summed (they add up to it): the service's for a period or a rolling
    /// window, so Home's, the Overview's, and the Daily view's period.
    /// - Parameter days: the aggregates of `days(for: period, ...)` (or `days(in:)` for a rolling window, `period` nil)
    static func summary(
        days: [DayAggregate],
        window: DateInterval,
        endRule: StatsEndRule,
        period: StatsPeriod?,
        bands: StatsBands
    ) -> GlucoseSummary {
        let counts = dayCounts(period, days: days)
        return summary(
            days.reduce(GlucoseHistogram()) { $0 + $1.histogram },
            window: window,
            endRule: endRule,
            calendarDays: counts.calendarDays,
            daysWithData: counts.daysWithData,
            bands: bands
        )
    }

    /// The one-day summary of a day of a period: the Trace's of that day (its window is the day up to E, counted as one
    /// day), the Trace strip's and the Daily view's.
    /// - Parameter day: an aggregate of `days(for: period, ...)`
    static func daySummary(_ day: DayAggregate, endRule: StatsEndRule, bands: StatsBands) -> GlucoseSummary {
        let counts = dayCounts(.today, days: [day])
        return summary(
            day.histogram,
            window: day.day,
            endRule: endRule,
            calendarDays: counts.calendarDays,
            daysWithData: counts.daysWithData,
            bands: bands
        )
    }

    /// - Parameter endRule: the rule that gave the window's end (`effectiveEndRule`)
    static func summary(
        _ h: GlucoseHistogram,
        window: DateInterval,
        endRule: StatsEndRule,
        calendarDays: Int,
        daysWithData: Int,
        bands: StatsBands
    ) -> GlucoseSummary {
        let total = h.totalSeconds
        let mean = h.mean
        let sd = h.sd
        let coverage = window.duration > 0 ? Swift.min(total / window.duration, 1) : 0

        return GlucoseSummary(
            window: window,
            endRule: endRule,
            histogram: h,
            calendarDays: calendarDays,
            daysWithData: daysWithData,
            bands: bands,
            bandShares: BandShares(seconds: GlucoseBand.allCases.map { seconds(h, in: $0, bands: bands) }, total: total),
            tirFraction: total > 0 ? h.seconds(in: bands.tirRange) / total : 0,
            titrFraction: total > 0 ? h.seconds(in: bands.titrRange) / total : 0,
            mean: mean,
            sd: sd,
            cv: mean.flatMap { mean in sd.map { mean > 0 ? $0 / mean * 100 : 0 } },
            gmiPercent: mean.map { Self.gmiPercent(meanMgdl: $0) },
            eA1cPercent: mean.map { Self.eA1cPercent(meanMgdl: $0) },
            coverage: coverage,
            coveragePercent: Int((coverage * 100).rounded())
        )
    }

    /// The seconds a histogram spent in a band (0 for a zero-width band).
    static func seconds(_ h: GlucoseHistogram, in band: GlucoseBand, bands: StatsBands) -> Double {
        bands.range(of: band).map { h.seconds(in: $0) } ?? 0
    }

    /// Whole percents summing to 100 (all 0 when the fractions are): the floors, plus one for each of the largest
    /// remainders (ties to the earlier index).
    static func largestRemainder(_ fractions: [Double]) -> [Int] {
        let total = fractions.reduce(0) { $0 + Swift.max($1, 0) }
        guard total > 0 else { return fractions.map { _ in 0 } }

        let scaled = fractions.map { Swift.max($0, 0) / total * 100 }
        var percents = scaled.map { Int($0.rounded(.down)) }
        let remainders = scaled.indices.map { scaled[$0] - Double(percents[$0]) }
        let missing = 100 - percents.reduce(0, +)
        let order = remainders.indices.sorted { remainders[$0] > remainders[$1] || (remainders[$0] == remainders[$1] && $0 < $1) }
        for index in order.prefix(Swift.max(missing, 0)) {
            percents[index] += 1
        }
        return percents
    }

    // MARK: - Glycemia Risk Index

    /// GRI's weight of the hypo component (Klonoff et al. 2022).
    static let griHypoWeight = 3.0
    /// GRI's weight of the hyper component.
    static let griHyperWeight = 1.6
    /// The low range's weight in the hypo component (very low counts in full).
    static let griLowWeight = 0.8
    /// The high range's weight in the hyper component (very high counts in full).
    static let griHighWeight = 0.5
    /// GRI's largest value: the published scale is 0...100.
    static let griCap = 100.0
    /// The width of each of GRI's five zones on the whole-number GRI: A 0–20, B 21–40, … E 81–100 (Klonoff et al.).
    static let griZoneWidth = 20

    /// The GRI of a histogram, nil without data. The ranges are the standard ones: very low below 54, low from 54 up to
    /// the bottom of `tirRange`, high above `tirRange` up to 250, very high above 250. So the low/high settings never
    /// change it; only the mmol users' `tirRange` top (181) moves the high range by its one value.
    static func gri(_ h: GlucoseHistogram, bands: StatsBands) -> GlycemiaRiskIndex? {
        let total = h.totalSeconds
        guard total > 0 else { return nil }
        func percent(_ range: ClosedRange<Int>) -> Double {
            h.seconds(in: range) / total * 100
        }
        let tir = bands.tirRange
        let veryLow = percent(0 ... StatsBands.veryLowBelow - 1)
        let low = StatsBands.veryLowBelow < tir.lowerBound ? percent(StatsBands.veryLowBelow ... tir.lowerBound - 1) : 0
        let high = tir.upperBound < StatsBands.veryHighAbove ? percent(tir.upperBound + 1 ... StatsBands.veryHighAbove) : 0
        let veryHigh = percent(StatsBands.veryHighAbove + 1 ... GlucoseHistogram.maxValue)
        let hypo = veryLow + griLowWeight * low
        let hyper = veryHigh + griHighWeight * high
        return GlycemiaRiskIndex(
            veryLow: veryLow,
            low: low,
            high: high,
            veryHigh: veryHigh,
            hypo: hypo,
            hyper: hyper,
            value: Swift.min(griHypoWeight * hypo + griHyperWeight * hyper, griCap)
        )
    }

    /// The zone of a GRI value, rounded to a whole number as the paper's zones are: A up to 20, B 21–40, C 41–60,
    /// D 61–80, E 81–100 (an edge is in the zone below it: 20 is A, 20.5 is 21, B).
    static func griZone(_ value: Double) -> GlycemiaRiskIndex.Zone {
        let rounded = Int(Swift.max(value, 0).rounded())
        let index = Swift.max(rounded - 1, 0) / griZoneWidth
        return GlycemiaRiskIndex.Zone(rawValue: Swift.min(index, GlycemiaRiskIndex.Zone.allCases.count - 1)) ?? .e
    }

    // MARK: - A1c estimates

    /// Glucose Management Indicator, %
    static func gmiPercent(meanMgdl: Double) -> Double {
        3.31 + 0.02392 * meanMgdl
    }

    /// ADAG estimated A1c, %
    static func eA1cPercent(meanMgdl: Double) -> Double {
        (meanMgdl + 46.7) / 28.7
    }

    /// mmol/mol
    static func ifcc(fromPercent percent: Double) -> Double {
        10.929 * (percent - 2.152)
    }

    // MARK: - Time of day

    /// Ambulatory glucose profile: `1440 / binMinutes` bins by local clock time, each pooled with `poolNeighbours` bins
    /// on either side (wrapping at midnight). A reading's whole span (clipped to the window) goes to its own clock time.
    /// nil for a bin without data. Percentiles are per distinct value (`GlucoseHistogram.quantile`).
    /// - Parameter window: the period's window; clips the spans, and leaves out the lookback readings before it
    static func agp(
        _ w: [WeightedPoint],
        calendar: Calendar,
        clippedTo window: DateInterval,
        binMinutes: Int = GlucoseStatsEngine.agpBinMinutes,
        poolNeighbours: Int = 1
    ) -> [AGPBin?] {
        let binMinutes = Swift.max(binMinutes, 1)
        let binCount = Swift.max(minutesPerDay / binMinutes, 1)
        let bins = clockHistograms(w, calendar: calendar, clippedTo: window, count: binCount) { minuteOfDay in
            minuteOfDay / binMinutes
        }
        return agpBins(bins, binMinutes: binMinutes, poolNeighbours: poolNeighbours)
    }

    /// The AGP of a list of days (`agp`'s bins and pooling): each reading's overlap with each of the days goes to its
    /// own clock time, so a reading across midnight into a day that isn't listed gives only its part in the listed one.
    /// The days of a window, listed, give `agp` of that window.
    /// - Parameter days: sorted oldest -> newest, not overlapping; need not be contiguous
    static func agp(
        _ w: [WeightedPoint],
        calendar: Calendar,
        days: [DateInterval],
        binMinutes: Int = GlucoseStatsEngine.agpBinMinutes,
        poolNeighbours: Int = 1
    ) -> [AGPBin?] {
        let binMinutes = Swift.max(binMinutes, 1)
        let binCount = Swift.max(minutesPerDay / binMinutes, 1)
        var bins = Array(repeating: GlucoseHistogram(), count: binCount)
        forEachOverlap(w, days: days, calendar: calendar) { point, minute, _, seconds, startsInside in
            bins[Swift.min(minute / binMinutes, binCount - 1)].add(point, seconds: seconds, startsInside: startsInside)
        }
        return agpBins(bins, binMinutes: binMinutes, poolNeighbours: poolNeighbours)
    }

    /// The AGP's bins from its clock histograms (one per bin, oldest minute first): each pooled with `poolNeighbours`
    /// bins on either side (wrapping at midnight), nil for a bin without data.
    static func agpBins(_ bins: [GlucoseHistogram], binMinutes: Int, poolNeighbours: Int) -> [AGPBin?] {
        let binCount = bins.count
        let pool = Swift.max(poolNeighbours, 0)
        return (0 ..< binCount).map { index -> AGPBin? in
            var pooled = GlucoseHistogram()
            for offset in -pool ... pool {
                pooled = pooled + bins[((index + offset) % binCount + binCount) % binCount]
            }
            guard pooled.totalSeconds > 0,
                  let p5 = pooled.quantile(0.05),
                  let p25 = pooled.quantile(0.25),
                  let p50 = pooled.quantile(0.5),
                  let p75 = pooled.quantile(0.75),
                  let p95 = pooled.quantile(0.95)
            else { return nil }
            return AGPBin(
                startMinute: index * binMinutes,
                p5: p5,
                p25: p25,
                p50: p50,
                p75: p75,
                p95: p95,
                seconds: pooled.totalSeconds
            )
        }
    }

    /// The point drawn at midnight (minute 1440): the average of the last and the first bin, nil unless both have data.
    static func agpMidnightEdge(_ bins: [AGPBin?]) -> AGPBin? {
        guard let last = bins.last ?? nil, let first = bins.first ?? nil else { return nil }
        return AGPBin(
            startMinute: minutesPerDay,
            p5: (last.p5 + first.p5) / 2,
            p25: (last.p25 + first.p25) / 2,
            p50: (last.p50 + first.p50) / 2,
            p75: (last.p75 + first.p75) / 2,
            p95: (last.p95 + first.p95) / 2,
            seconds: (last.seconds + first.seconds) / 2
        )
    }

    /// 24 clock-hour histograms; a reading's whole span (clipped to the window) goes to its own clock hour.
    /// - Parameter window: the period's window; clips the spans, and leaves out the lookback readings before it
    static func hourOfDay(_ w: [WeightedPoint], calendar: Calendar, clippedTo window: DateInterval) -> [HourBucket] {
        clockHistograms(w, calendar: calendar, clippedTo: window, count: 24) { $0 / 60 }
            .enumerated()
            .map { HourBucket(hour: $0.offset, histogram: $0.element) }
    }

    /// "When it happens": for below / in range / above, the hour with the largest share of its hour's time **as shown**:
    /// the highest `peakPercent` (the sum of the hour's largest-remainder band percents), then the highest share, ties to
    /// the earliest hour. So the percent shown is the hour's own rows' sum and the largest any hour shows (2.5 + 2.5 %
    /// that rounds to 3 + 3 = 6 % beats a 5.1 % shown as 5 %). Shares closer than `peakShareTolerance` are a tie: the
    /// time in a band and the hour's total are summed in different orders, so two hours all in range can be 1 and
    /// 0.9999999999. A group whose largest share is 0 is left out.
    static func peakHours(_ buckets: [HourBucket], bands: StatsBands) -> [PeakHour] {
        let hours = buckets
            .sorted { $0.hour < $1.hour }
            .filter { $0.histogram.totalSeconds > 0 }
            .map { (bucket: $0, hour: hourOfDayHour($0, bands: bands)) }
        return PeakHour.Group.allCases.compactMap { group -> PeakHour? in
            var best: (peak: PeakHour, percent: Int)?
            for (bucket, hour) in hours {
                let share = seconds(bucket.histogram, in: group, bands: bands) / bucket.histogram.totalSeconds
                guard share > 0 else { continue }
                let peak = PeakHour(group: group, hour: bucket.hour, share: share)
                let percent = peakPercent(peak, of: hour).percent
                if let best, !ranksAbove(percent: percent, share: share, best: best) {
                    continue
                }
                best = (peak, percent)
            }
            return best?.peak
        }
    }

    /// Shares closer than this are equal (`peakHours`): far below a displayed percent, far above summation noise.
    static let peakShareTolerance = 1E-9

    /// A higher percent shown, or the same one and a share higher beyond the noise (`peakHours`).
    private static func ranksAbove(percent: Int, share: Double, best: (peak: PeakHour, percent: Int)) -> Bool {
        guard percent == best.percent else { return percent > best.percent }
        return share - best.peak.share > peakShareTolerance
    }

    static func seconds(_ h: GlucoseHistogram, in group: PeakHour.Group, bands: StatsBands) -> Double {
        group.bands.reduce(0) { $0 + seconds(h, in: $1, bands: bands) }
    }

    /// An hour of the Hour-of-day view: its column (the nonzero visible bands stacked from very low up, fractions of its
    /// covered time) and its band percents (largest remainder, "<1%" when nonzero but rounded to 0). Without data: no
    /// column, all 0.
    /// - Parameter bucket: one of `hourOfDay`'s
    static func hourOfDayHour(_ bucket: HourBucket, bands: StatsBands) -> HourOfDayHour {
        let h = bucket.histogram
        let total = h.totalSeconds
        let shares = BandShares(seconds: GlucoseBand.allCases.map { seconds(h, in: $0, bands: bands) }, total: total)
        return HourOfDayHour(
            hour: bucket.hour,
            seconds: total,
            segments: shares.stacked(bands.visibleBands),
            bandShares: shares
        )
    }

    /// "When it happens", as shown: the peak's share as the sum of its hour's band percents (largest remainder), so it
    /// is the number the hour's rows add up to when that hour is selected; `belowOne` ("<1%") when the share is nonzero
    /// but that sum is 0.
    /// - Parameter hour: the peak hour's (`hourOfDayHour`), the same bands
    static func peakPercent(_ peak: PeakHour, of hour: HourOfDayHour) -> (percent: Int, belowOne: Bool) {
        let percent = peak.group.bands.reduce(0) { $0 + hour.percent($1) }
        return (percent, peak.share > 0 && percent == 0)
    }

    /// The local clock hour of a moment (the Hour-of-day view opens at the current one): the hour-of-day rule, so the
    /// repeated hour of a DST change is the same hour twice.
    static func clockHour(of date: Date, calendar: Calendar) -> Int {
        agpBin(of: date, calendar: calendar, binCount: 24)
    }

    /// `offset` hours on from `hour`, wrapping around midnight.
    static func hourStep(_ hour: Int, by offset: Int) -> Int {
        agpStep(hour, by: offset, binCount: 24)
    }

    // MARK: - Charts

    /// The glucose axis of Trace and AGP, mg/dL: 40...300, raised to 40...400 when a plotted value (a Trace reading, an
    /// AGP p95) is above 300.
    /// - Parameter highest: the highest value plotted, nil when nothing is
    static func glucoseAxis(highest: Double?) -> ClosedRange<Int> {
        (highest ?? 0) > 300 ? 40 ... 400 : 40 ... 300
    }

    /// The dashed levels of Trace and AGP: 54, the TIR's upper edge (180, mmol 181) and 250, those inside the axis and
    /// not where a range edge (low, high; drawn solid) is.
    static func dashedLevels(bands: StatsBands, axis: ClosedRange<Int>) -> [Int] {
        [StatsBands.veryLowBelow, bands.tirRange.upperBound, StatsBands.veryHighAbove]
            .filter { $0 != bands.low && $0 != bands.high && axis.contains($0) }
    }

    /// The labelled glucose levels of Trace and AGP, ascending. Taken in order of importance (low, high, the axis top,
    /// the TIR's upper edge, 250), those inside the axis; a level closer than 7% of the axis to one already labelled is
    /// left out (high 170 hides 180).
    static func labelledLevels(bands: StatsBands, axis: ClosedRange<Int>) -> [Int] {
        let candidates = [bands.low, bands.high, axis.upperBound, bands.tirRange.upperBound, StatsBands.veryHighAbove]
        let minimumGap = Double(axis.upperBound - axis.lowerBound) * 0.07
        var labels: [Int] = []
        for value in candidates where axis.contains(value) {
            guard labels.allSatisfy({ Double(abs($0 - value)) >= minimumGap }) else { continue }
            labels.append(value)
        }
        return labels.sorted()
    }

    /// The local clock times `hh:00`, `hh` a multiple of `everyHours` (00/06/12/18 by default), inside
    /// `[domain.start, domain.end)`, oldest -> newest. Real dates: a 24-hour domain across midnight gets the ticks of
    /// both days, and a DST day still gets its clock times (not every 6 hours of elapsed time).
    static func clockTicks(in domain: DateInterval, everyHours: Int = 6, calendar: Calendar) -> [Date] {
        let step = Swift.min(Swift.max(everyHours, 1), 24)
        var ticks: [Date] = []
        for day in StatsClock.calendarDays(in: domain, calendar: calendar) {
            for hour in stride(from: 0, to: 24, by: step) {
                guard let tick = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start),
                      domain.start <= tick, domain.end > tick, (ticks.last ?? .distantPast) < tick
                else { continue }
                ticks.append(tick)
            }
        }
        return ticks
    }

    /// The index of the item nearest to `date` (the earlier one on a tie), nil when there are none. A binary search:
    /// the Trace's selection runs it on every move of the finger.
    /// - Parameter sorted: oldest -> newest by `time`
    static func nearestIndex<T>(to date: Date, in sorted: [T], time: (T) -> Date) -> Int? {
        guard sorted.isNotEmpty else { return nil }
        // the first one at or after the date
        let low = sorted.partitionIndex { time($0) >= date }
        guard low < sorted.count else { return sorted.count - 1 }
        guard low > 0 else { return 0 }
        let before = date.timeIntervalSince(time(sorted[low - 1]))
        let after = time(sorted[low]).timeIntervalSince(date)
        return before <= after ? low - 1 : low
    }

    // MARK: - Trace

    /// The 24 h's end is labelled "now": no clock tick this close before it.
    static let traceNowTickGap: TimeInterval = .minutes(90)

    /// The readings to draw, in the given order, each with its band and its value kept inside the axis (a reading off
    /// the axis is drawn at its edge).
    static func tracePoints(_ w: [WeightedPoint], axis: ClosedRange<Int>, bands: StatsBands) -> [TracePoint] {
        w.map { point in
            let mgdl = Int(point.mgdl)
            return TracePoint(
                time: point.time,
                mgdl: mgdl,
                plotted: Swift.min(Swift.max(mgdl, axis.lowerBound), axis.upperBound),
                band: bands.band(mgdl)
            )
        }
    }

    /// The Trace's x ticks: the clock ticks (`clockTicks`); with the end labelled "now" (the 24 h), none within
    /// `traceNowTickGap` before it.
    static func traceTicks(in domain: DateInterval, endsNow: Bool, calendar: Calendar) -> [Date] {
        let ticks = clockTicks(in: domain, calendar: calendar)
        guard endsNow else { return ticks }
        return ticks.filter { domain.end.timeIntervalSince($0) >= traceNowTickGap }
    }

    /// A day of the Trace's strip: in range from its own one-day summary; it has readings when a reading starts in it (the previous evening's span running past midnight
    /// is covered time, not a reading).
    /// - Parameter day: an aggregate of `days(for: period, ...)`
    static func traceStripDay(_ day: DayAggregate, endRule: StatsEndRule, bands: StatsBands) -> TraceStripDay {
        let oneDay = daySummary(day, endRule: endRule, bands: bands)
        return TraceStripDay(
            start: day.day.start,
            hasReadings: day.histogram.readingCount > 0,
            inRangeFraction: oneDay.fraction(.inRange)
        )
    }

    // MARK: - AGP chart

    /// The AGP's bins: 15 minutes of the clock each, 96 a day.
    static let agpBinMinutes = 15
    /// Fewer days with data make a limited AGP (the consensus minimum), whatever the coverage.
    static let agpMinimumDays = 14

    /// The AGP is limited data with fewer than `agpMinimumDays` days with data (so also in a shorter period), or with
    /// limited coverage (`isLimited`, the Overview's rule).
    static func agpIsLimited(_ summary: GlucoseSummary) -> Bool {
        summary.daysWithData < agpMinimumDays || summary.isLimited
    }

    /// The minute of the day a bin is drawn at: its middle, rounded down (7 for 00:00-00:15; half a minute is far below
    /// a point of the chart).
    static func agpMiddleMinute(ofBin bin: Int, binCount: Int) -> Int {
        let binMinutes = minutesPerDay / Swift.max(binCount, 1)
        return bin * binMinutes + binMinutes / 2
    }

    /// The bin a minute of the day falls in (a selection snaps to it); minutes outside the day are kept inside it.
    static func agpBin(atMinute minute: Int, binCount: Int) -> Int {
        let count = Swift.max(binCount, 1)
        let binMinutes = Swift.max(minutesPerDay / count, 1)
        let clamped = Swift.min(Swift.max(minute, 0), minutesPerDay - 1)
        return Swift.min(clamped / binMinutes, count - 1)
    }

    /// The bin of a moment's local clock time (the AGP opens at the current one).
    static func agpBin(of date: Date, calendar: Calendar, binCount: Int) -> Int {
        agpBin(atMinute: StatsClock.minuteOfDay(date, in: calendar.timeZone), binCount: binCount)
    }

    /// `offset` bins on from `bin`, wrapping around midnight (the profile is one day).
    static func agpStep(_ bin: Int, by offset: Int, binCount: Int) -> Int {
        let count = Swift.max(binCount, 1)
        return ((bin + offset) % count + count) % count
    }

    /// The AGP's glucose axis (`glucoseAxis`): raised when a p95 is above 300.
    static func agpAxis(_ bins: [AGPBin?]) -> ClosedRange<Int> {
        glucoseAxis(highest: bins.compactMap { $0?.p95 }.max())
    }

    /// What the AGP chart draws: each bin with data at its middle minute (`agpMiddleMinute`), and the midnight edge
    /// (`agpMidnightEdge`) at minute 0 and 1440 when there is one; the percentiles kept inside the axis. A bin without
    /// data is a gap: the points after it are a new segment (each segment is drawn on its own).
    /// No segment is a single point (nothing to draw): a raw bin with data gives three pooled bins with data, and a run
    /// split at midnight keeps the edge point on both sides.
    /// - Parameter bins: `agp`'s, oldest minute first
    static func agpPlotPoints(_ bins: [AGPBin?], axis: ClosedRange<Int>) -> [AGPPlotPoint] {
        guard bins.isNotEmpty else { return [] }
        let lower = Double(axis.lowerBound)
        let upper = Double(axis.upperBound)
        func clamped(_ value: Double) -> Double {
            Swift.min(Swift.max(value, lower), upper)
        }

        var points: [AGPPlotPoint] = []
        var segment = 0
        func append(_ bin: AGPBin, at minute: Int) {
            points.append(
                AGPPlotPoint(
                    minute: minute,
                    segment: segment,
                    p5: clamped(bin.p5),
                    p25: clamped(bin.p25),
                    p50: clamped(bin.p50),
                    p75: clamped(bin.p75),
                    p95: clamped(bin.p95)
                )
            )
        }

        let edge = agpMidnightEdge(bins)
        if let edge {
            append(edge, at: 0)
        }
        for (index, bin) in bins.enumerated() {
            guard let bin else {
                // the first gap after a point ends its segment
                if points.last?.segment == segment {
                    segment += 1
                }
                continue
            }
            append(bin, at: agpMiddleMinute(ofBin: index, binCount: bins.count))
        }
        if let edge {
            append(edge, at: minutesPerDay)
        }
        return points
    }

    // MARK: - Usual day overlay

    /// The fewest days with readings the Day tab's usual day is drawn with; below it the overlay is left out (one line
    /// says so). Below `agpMinimumDays` (or with limited coverage) it is drawn and marked limited, as the AGP is
    /// (`agpIsLimited`).
    static let usualDayMinimumDays = 3

    /// The usual day is drawn: its baseline (the AGP of the last N days) has at least `usualDayMinimumDays` days with
    /// readings.
    static func usualDayIsDrawn(_ summary: GlucoseSummary) -> Bool {
        summary.daysWithData >= usualDayMinimumDays
    }

    /// The AGP's points placed on the Day tab's x domain (a whole day, or the 24 hours across midnight): each at its
    /// local clock minute on every calendar day the domain touches, so the 24 hours get the evening of one day and the
    /// morning of the next. The 25-hour day's repeated hour repeats the band, the 23-hour day's skipped hour has none
    /// (the clock rule of `agp`). Oldest -> newest; consecutive points more than a bin apart in real time (a gap in the
    /// profile) start a new segment. Clipped to the domain, the band interpolated at its edges, so it reaches them; a
    /// segment of a single point (nothing to draw) is left out.
    /// - Parameters:
    ///   - points: `agpPlotPoints` of the baseline's bins, kept inside the Trace's axis
    ///   - binMinutes: the profile's bins: consecutive points are at most this far apart
    static func usualDayPoints(
        _ points: [AGPPlotPoint],
        domain: DateInterval,
        calendar: Calendar,
        binMinutes: Int = GlucoseStatsEngine.agpBinMinutes
    ) -> [UsualDayPoint] {
        guard points.isNotEmpty, domain.duration > 0 else { return [] }
        let step = TimeInterval.minutes(Swift.max(binMinutes, 1))
        let timeZone = calendar.timeZone

        // every point on each calendar day touching the domain, or a bin beyond it (for the edges' interpolation)
        let reach = DateInterval(start: domain.start.addingTimeInterval(-step), end: domain.end.addingTimeInterval(step))
        var placed: [(time: Date, point: AGPPlotPoint)] = []
        for day in StatsClock.calendarDays(in: reach, calendar: calendar) {
            let clock = StatsClock.ClockDay(day, timeZone: timeZone)
            for point in points {
                // the moments whose clock shows the minute: one, two in a repeated hour, none in a skipped one
                for time in clock.times(minute: point.minute, throughEnd: true) {
                    placed.append((time, point))
                }
            }
        }
        placed.sort { $0.time < $1.time }

        // runs of points a bin apart at most; one day's 24:00 is the next day's 00:00 (the same edge), kept once
        var runs: [[(time: Date, point: AGPPlotPoint)]] = []
        for entry in placed {
            guard let last = runs.last?.last, entry.time.timeIntervalSince(last.time) <= step else {
                runs.append([entry])
                continue
            }
            if entry.time != last.time {
                runs[runs.count - 1].append(entry)
            }
        }

        func values(_ point: AGPPlotPoint) -> (p25: Double, p50: Double, p75: Double) {
            (point.p25, point.p50, point.p75)
        }
        func interpolated(
            _ a: (time: Date, point: AGPPlotPoint),
            _ b: (time: Date, point: AGPPlotPoint),
            at time: Date
        ) -> (p25: Double, p50: Double, p75: Double) {
            let fraction = time.timeIntervalSince(a.time) / b.time.timeIntervalSince(a.time)
            func value(_ lower: Double, _ upper: Double) -> Double {
                lower + (upper - lower) * fraction
            }
            return (value(a.point.p25, b.point.p25), value(a.point.p50, b.point.p50), value(a.point.p75, b.point.p75))
        }

        var result: [UsualDayPoint] = []
        var segment = 0
        for run in runs {
            var clipped: [(time: Date, values: (p25: Double, p50: Double, p75: Double))] = []
            for index in run.indices {
                let entry = run[index]
                if index > 0 {
                    let previous = run[index - 1]
                    // the run crosses an edge between the two: the band at the edge
                    for edge in [domain.start, domain.end] where previous.time < edge && edge < entry.time {
                        clipped.append((edge, interpolated(previous, entry, at: edge)))
                    }
                }
                if domain.start <= entry.time, entry.time <= domain.end {
                    clipped.append((entry.time, values(entry.point)))
                }
            }
            guard clipped.count >= 2 else { continue }
            result += clipped.map {
                UsualDayPoint(time: $0.time, segment: segment, p25: $0.values.p25, p50: $0.values.p50, p75: $0.values.p75)
            }
            segment += 1
        }
        return result
    }

    /// A readings change reaches the usual day's baseline enough to reload it: everything changed (`interval` nil:
    /// a wipe, a time zone change), a day before today (a backfill, a delete, a recalibration; the previous reading's
    /// span just after midnight), or a change was missed in between (only the newest is delivered after the
    /// background). A reading of today alone doesn't: it is 1/N of the baseline, and reloading it is an AGP of N days.
    /// - Parameters:
    ///   - seenSeq: the newest change the baseline accounts for; an older or equal one doesn't reach it
    ///   - today: the start of today
    static func usualDayIsReached(by change: StatsChange, seenSeq: Int, today: Date) -> Bool {
        guard change.seq > seenSeq else { return false }
        guard change.seq == seenSeq + 1, let interval = change.interval else { return true }
        return interval.start < today
    }

    // MARK: - Picking a day

    /// The day of a period the Trace shows for the day picked on it, nil for today (it follows midnight):
    /// the picked day kept inside the period (the nearest of its days), so switching the period keeps a valid day and
    /// switching back restores the picked one. nil without a pick, for Today and 24 h, and when it is today.
    /// - Parameters:
    ///   - picked: the start of the day picked, nil for today
    ///   - today: the start of today
    static func shownDay(_ picked: Date?, period: StatsPeriod, today: Date, calendar: Calendar) -> Date? {
        guard let picked, let count = period.calendarDayCount else { return nil }
        let first = StatsClock.dayStart(count - 1, before: today, calendar: calendar) ?? today
        let day = Swift.min(Swift.max(calendar.startOfDay(for: picked), first), today)
        return day < today ? day : nil
    }

    /// The index of the day the date falls in (a tap on a chart of days); a date before the first day is in the first
    /// one, after the last day in the last one. nil without days.
    /// - Parameter days: oldest -> newest, back to back
    static func dayIndex(containing date: Date, in days: [DateInterval]) -> Int? {
        guard days.isNotEmpty else { return nil }
        // the first day starting after the date
        let low = days.partitionIndex { $0.start > date }
        return Swift.max(low - 1, 0)
    }

    // MARK: - Daily

    /// The Daily chart shows this many days at once (fewer in a shorter period) and scrolls through the rest.
    static let dailyVisibleDays = 12
    /// At the larger text sizes (above `.large`) fewer, so the two-line date labels don't collide.
    static let dailyVisibleDaysLargeText = 8

    /// A day of the Daily view: its bar (the nonzero bands stacked from very low up, fractions of its covered time) and
    /// the numbers of its one-day summary (`daySummary`), so the Trace's of that day. A day without a reading starting
    /// in it has no bar (the previous evening's span running past midnight is covered time, not a reading).
    /// - Parameter day: an aggregate of `days(for: period, ...)`; the last one, today, is clipped to E
    static func dailyDay(_ day: DayAggregate, endRule: StatsEndRule, bands: StatsBands, calendar: Calendar) -> DailyDay {
        let oneDay = daySummary(day, endRule: endRule, bands: bands)
        let hasReadings = day.histogram.readingCount > 0
        let start = calendar.startOfDay(for: day.day.start)
        return DailyDay(
            day: DateInterval(start: start, end: StatsClock.endOfDay(start, calendar: calendar)),
            hasReadings: hasReadings,
            segments: hasReadings ? oneDay.bandShares.stacked(bands.visibleBands) : [],
            bandShares: oneDay.bandShares,
            tirPercent: oneDay.tirPercent,
            titrPercent: oneDay.titrPercent,
            mean: oneDay.mean,
            cv: oneDay.cv,
            coveragePercent: oneDay.coveragePercent,
            secondsBelowLow: seconds(day.histogram, in: PeakHour.Group.below, bands: bands)
        )
    }

    /// The first day the Daily chart shows (its scroll position), so that the selected day is visible: from `leading`
    /// as little scrolling as needed; without one (the chart opening, a new period) the selected day at the trailing end
    /// (today: the newest days, as the period ends). Always a full screen of days inside the period.
    /// - Parameters:
    ///   - selected: the index of the selected day
    ///   - leading: the index of the first day shown now, nil to open
    static func dailyLeadingDay(showing selected: Int, from leading: Int?, dayCount: Int, visibleDays: Int) -> Int {
        let visible = Swift.min(Swift.max(visibleDays, 1), Swift.max(dayCount, 1))
        let last = Swift.max(dayCount - visible, 0)
        let selected = Swift.min(Swift.max(selected, 0), Swift.max(dayCount - 1, 0))
        var first = leading ?? selected - visible + 1
        if selected < first {
            first = selected
        }
        if selected >= first + visible {
            first = selected - visible + 1
        }
        return Swift.min(Swift.max(first, 0), last)
    }

    // MARK: - Weeks

    /// Week k is the days `[first + 7k, first + 7k + 7)`; the last week includes today. With a day count that isn't
    /// a multiple of 7 the last week is short.
    /// - Parameter days: the aggregates of `days(for: .weeks5/.weeks13, ...)`, the last one today (zero-length just
    ///   after midnight)
    static func weeks(_ days: [DayAggregate], count: Int) -> [WeekAggregate] {
        let days = days.sorted { $0.day.start < $1.day.start }
        var weeks: [WeekAggregate] = []
        for week in 0 ..< Swift.max(count, 0) {
            let lower = week * 7
            guard lower < days.count else { break }
            let upper = Swift.min(lower + 7, days.count)
            let slice = days[lower ..< upper]
            weeks.append(
                WeekAggregate(
                    days: DateInterval(start: slice[lower].day.start, end: slice[upper - 1].day.end),
                    lastDay: slice[upper - 1].day.start,
                    dayCount: upper - lower,
                    histogram: slice.reduce(GlucoseHistogram()) { $0 + $1.histogram },
                    includesToday: upper == days.count
                )
            )
        }
        return weeks
    }

    // MARK: - Weekly

    /// The mean as the Weekly view shows it, and takes its Δ from: whole mg/dL (rounded as `StatsFormatting.glucose`
    /// rounds a mean), or mmol/L to one decimal (`StatsBands.mmolDisplay`).
    static func shownMean(_ mgdl: Double, units: GlucoseUnits) -> Decimal {
        switch units {
        case .mgdL:
            return Decimal(Int(mgdl.rounded()))
        case .mmolL:
            return StatsBands.mmolDisplay(decimal: Decimal(mgdl))
        }
    }

    /// A week of the Weekly view against the period (`average`, the window's summary: the Overview's): Δ = the week as
    /// shown − the period as shown. In range: largest remainder of the week's own bands against the period's in-range
    /// percent; mean: `shownMean` of both, so in mmol/L the difference of the two displayed values. A week no reading
    /// starts in has no data: no numbers, no Δ.
    /// - Parameter week: one of `weeks`' over the days of the period of `average`
    static func weeklyWeek(_ week: WeekAggregate, average: GlucoseSummary, units: GlucoseUnits) -> WeeklyWeek {
        let h = week.histogram
        let total = h.totalSeconds
        guard !week.isEmpty, total > 0 else {
            return WeeklyWeek(
                days: week.days,
                lastDay: week.lastDay,
                dayCount: week.dayCount,
                includesToday: week.includesToday,
                hasData: false,
                inRangePercent: nil,
                inRangeBelowOnePercent: false,
                mean: nil,
                inRangeDelta: nil,
                meanDelta: nil
            )
        }
        let bands = average.bands
        let shares = BandShares(seconds: GlucoseBand.allCases.map { seconds(h, in: $0, bands: bands) }, total: total)
        let inRange = shares.percent(.inRange)
        let mean = h.mean.map { shownMean($0, units: units) }
        let averageMean = average.mean.map { shownMean($0, units: units) }
        return WeeklyWeek(
            days: week.days,
            lastDay: week.lastDay,
            dayCount: week.dayCount,
            includesToday: week.includesToday,
            hasData: true,
            inRangePercent: inRange,
            inRangeBelowOnePercent: shares.isBelowOnePercent(.inRange),
            mean: mean,
            inRangeDelta: inRange - average.percent(.inRange),
            meanDelta: mean.flatMap { mean in averageMean.map { mean - $0 } }
        )
    }

    /// The steps of the Weekly charts' scale: in range 5 percentage points, the mean 10 mg/dL or 0.5 mmol/L.
    static let weeklyInRangeStep = 5.0
    static func weeklyMeanStep(units: GlucoseUnits) -> Double {
        units == .mmolL ? 0.5 : 10
    }

    /// How far a Weekly chart reaches above and below the average (its line, in the middle): the farthest week, up to a
    /// whole number of `step`s, at least one. The weeks without data (nil) are left out.
    /// - Parameter values: the weeks as shown, in the units of `average` and `step`
    static func weeklyHalfRange(_ values: [Double?], average: Double, step: Double) -> Double {
        guard step > 0 else { return 0 }
        let farthest = values.compactMap { $0 }.map { abs($0 - average) }.max() ?? 0
        // a hair under a whole step (a Decimal turned into a Double) is that step, not one more
        let steps = Swift.max((farthest / step - 1E-9).rounded(.up), 1)
        return steps * step
    }

    /// A Weekly bar is at least this part of the half range tall: a week at the average (or next to it) is still seen.
    static let weeklyMinimumBar = 0.04

    /// A week's bar: from the average to the week's value, at least `weeklyMinimumBar` of the half range tall (away from
    /// the average); a week at the average gets that much across the line.
    static func weeklyBar(_ value: Double, average: Double, halfRange: Double) -> (lower: Double, upper: Double) {
        let minimum = halfRange * weeklyMinimumBar
        if value > average {
            return (average, Swift.max(value, average + minimum))
        }
        if value < average {
            return (Swift.min(value, average - minimum), average)
        }
        return (average - minimum / 2, average + minimum / 2)
    }

    /// The weeks labelled on a Weekly chart's axis: every week of up to 6, otherwise every third from the first (13
    /// weeks: the 1st, 4th, 7th, 10th and 13th, so also this week).
    static func weeklyTickWeeks(count: Int) -> [Int] {
        Array(stride(from: 0, to: Swift.max(count, 0), by: count > 6 ? 3 : 1))
    }

    // MARK: - By weekday

    /// A cell (an hour, or a 3-hour block) with less covered time than this per hour of it is few: hatched and dimmed,
    /// "take it as a hint". Covered time, so the same at any cadence: 180 readings of a 1-minute sensor, 36 of a 5-minute
    /// one.
    static let weekdayFewHours = 3.0
    /// The heatmap's 3-hour blocks (at the larger text sizes): 00–03 … 21–24.
    static let weekdayBlockHours = 3

    /// By weekday's days: the `weeks` × 7 whole calendar days (23, 24 or 25 h) to yesterday, oldest -> newest, so every
    /// weekday the same number of times; today counts once it is over. None without weeks.
    /// - Parameter today: the start of today
    static func weekdayDays(weeks: Int, today: Date, calendar: Calendar) -> [DateInterval] {
        completeDays(count: Swift.max(weeks, 0) * 7, today: today, calendar: calendar)
    }

    /// The `count` whole calendar days (23, 24 or 25 h) to yesterday, oldest -> newest: today counts once it is over.
    /// None without a count.
    /// - Parameter today: a moment of today
    static func completeDays(count: Int, today: Date, calendar: Calendar) -> [DateInterval] {
        let today = calendar.startOfDay(for: today)
        return (0 ..< Swift.max(count, 0)).reversed().map { back in
            let start = StatsClock.dayStart(back + 1, before: today, calendar: calendar)
                ?? today.addingTimeInterval(-.days(back + 1))
            return DateInterval(start: start, end: StatsClock.endOfDay(start, calendar: calendar))
        }
    }

    /// By weekday's columns, the order shown: the `Calendar` weekdays (1 Sunday … 7 Saturday) of the locale's workdays
    /// in their order, then its weekend (`Calendar.nextWeekend`, after `date`), whatever the locale's first weekday:
    /// Mon … Fri, Sat, Sun for a Saturday–Sunday weekend (a Sunday-first locale too), Sun … Thu, Fri, Sat for a
    /// Friday–Saturday one. Without a weekend, the week from the locale's first weekday.
    static func weekdayOrder(calendar: Calendar, around date: Date) -> (order: [Int], weekend: [Int]) {
        weekdayOrder(weekend: weekend(calendar: calendar, around: date), firstWeekday: calendar.firstWeekday)
    }

    /// The weekend's `Calendar` weekdays in their order (`Calendar.nextWeekend` after `date`, each day checked with
    /// `isDateInWeekend`); empty without one.
    static func weekend(calendar: Calendar, around date: Date) -> [Int] {
        var weekend: [Int] = []
        if let next = calendar.nextWeekend(startingAfter: calendar.startOfDay(for: date)) {
            var day = calendar.startOfDay(for: next.start)
            while day < next.end, weekend.count < 7 {
                let weekday = calendar.component(.weekday, from: day)
                // a day of it, as the calendar says (never one twice)
                if calendar.isDateInWeekend(day), !weekend.contains(weekday) {
                    weekend.append(weekday)
                }
                guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = calendar.startOfDay(for: following)
            }
        }
        return weekend
    }

    /// `weekdayOrder` of a weekend (`Calendar` weekdays in their order): the week that ends with it; without one (or a
    /// week all weekend), the week from `firstWeekday` and no weekend.
    static func weekdayOrder(weekend: [Int], firstWeekday: Int) -> (order: [Int], weekend: [Int]) {
        let weekend = weekend.filter { (1 ... 7).contains($0) }
        // the week that ends with the weekend
        let first = weekend.last.map { $0 % 7 + 1 } ?? Swift.min(Swift.max(firstWeekday, 1), 7)
        let order = (0 ..< 7).map { (first - 1 + $0) % 7 + 1 }
        guard weekend.isNotEmpty, weekend.count < 7 else { return (order, []) }
        return (order.filter { !weekend.contains($0) } + weekend, weekend)
    }

    /// By weekday's pooling: the readings of the period's days by weekday and local clock hour (and 3-hour block), with
    /// the bands' seconds of the request, and the columns' order by the same calendar. A reading's span, clipped to the
    /// period, goes to the clock hour of the reading (By hour's rule, `hourOfDay`: the repeated hour of a DST change is
    /// that hour twice, the skipped one has none) on the day its clipped start is in: a span across midnight stays with
    /// its reading's hour and day, and the lookback reading before the period's first midnight gives its minutes after it
    /// to its own clock hour (the previous evening's) of the first day, as By hour gives them to that hour. So the cells
    /// summed by hour are `hourOfDay` of the period. A day or a cell has a reading when one starts in it.
    /// - Parameters:
    ///   - w: weighed, oldest -> newest; from the lookback before the first day on
    ///   - days: `weekdayDays`'
    static func weekdayHours(
        _ w: [WeightedPoint],
        days: [DateInterval],
        bands: StatsBands,
        calendar: Calendar
    ) -> WeekdayHours {
        let blockCount = 24 / weekdayBlockHours
        var hours = Array(repeating: Array(repeating: WeekdayCell(), count: 24), count: 7)
        var blocks = Array(repeating: Array(repeating: WeekdayCell(), count: blockCount), count: 7)
        var dayCounts = Array(repeating: 0, count: 7)
        var daysWithData = Array(repeating: 0, count: 7)
        let weekdays = days.map { calendar.component(.weekday, from: $0.start) - 1 }
        for weekday in weekdays {
            dayCounts[weekday] += 1
        }
        let shown = weekdayOrder(calendar: calendar, around: days.last?.start ?? Date())
        guard let first = days.first, let last = days.last else {
            return WeekdayHours(
                days: days,
                hours: hours,
                blocks: blocks,
                dayCounts: dayCounts,
                daysWithData: daysWithData,
                firstReading: nil,
                firstDayWithData: nil,
                order: shown.order,
                weekend: shown.weekend
            )
        }
        let window = DateInterval(start: first.start, end: last.end)

        // the last day counted for each cell and day (readings come oldest -> newest)
        var hourDay = Array(repeating: Array(repeating: -1, count: 24), count: 7)
        var blockDay = Array(repeating: Array(repeating: -1, count: blockCount), count: 7)
        var dayHasReading = Array(repeating: false, count: days.count)
        var firstReading: Date?
        var firstDayWithData: Date?
        var offsets = ZoneOffsets(calendar.timeZone)
        var dayIndex = 0
        for point in w {
            let seconds = StatsIntervals.overlap(from: point.time, to: point.end, in: window)
            guard seconds > 0 else { continue }
            let start = Swift.max(point.time, window.start)
            while dayIndex + 1 < days.count, days[dayIndex + 1].start <= start {
                dayIndex += 1
            }
            let weekday = weekdays[dayIndex]
            // the reading's own clock hour, as the By hour aggregate (`GlucoseStatsEngine.hourOfDay`; the lookback reading's too)
            let hour = StatsClock.minuteOfDay(point.time, secondsFromGMT: offsets.secondsFromGMT(for: point.time)) / 60
            let block = hour / weekdayBlockHours
            let startsInside = point.time >= window.start && point.time < window.end
            hours[weekday][hour].tally.add(point, seconds: seconds, startsInside: startsInside, bands: bands)
            blocks[weekday][block].tally.add(point, seconds: seconds, startsInside: startsInside, bands: bands)
            guard startsInside else { continue }
            firstReading = firstReading ?? point.time
            firstDayWithData = firstDayWithData ?? days[dayIndex].start
            if !dayHasReading[dayIndex] {
                dayHasReading[dayIndex] = true
                daysWithData[weekday] += 1
            }
            if hourDay[weekday][hour] != dayIndex {
                hourDay[weekday][hour] = dayIndex
                hours[weekday][hour].days += 1
            }
            if blockDay[weekday][block] != dayIndex {
                blockDay[weekday][block] = dayIndex
                blocks[weekday][block].days += 1
            }
        }
        return WeekdayHours(
            days: days,
            hours: hours,
            blocks: blocks,
            dayCounts: dayCounts,
            daysWithData: daysWithData,
            firstReading: firstReading,
            firstDayWithData: firstDayWithData,
            order: shown.order,
            weekend: shown.weekend
        )
    }

    /// A pool as By weekday shows it: its bands' fractions and largest-remainder percents ("<1%" when nonzero but
    /// rounded to 0), low and high as the sums of their two bands' percents, the mean.
    /// - Parameters:
    ///   - tally: summed from `weekdayHours`' cells, with `bands`
    ///   - hoursPerCell: a cell's hours (1, or `weekdayBlockHours`): under `weekdayFewHours` of covered time for each is
    ///     few; nil for a pool that isn't a cell (a weekday, the usual, the workdays), never few
    static func weekdayPool(_ tally: WeekdayTally, days: Int, hoursPerCell: Int?) -> WeekdayPool {
        let total = tally.seconds
        let shares = BandShares(seconds: tally.bandSeconds, total: total)
        func sum(_ group: PeakHour.Group) -> (percent: Int, belowOne: Bool) {
            let percent = group.bands.reduce(0) { $0 + shares.percent($1) }
            let fraction = group.bands.reduce(0) { $0 + shares.fraction($1) }
            return (percent, fraction > 0 && percent == 0)
        }
        let low = sum(.below)
        let high = sum(.above)
        let fewBelow = hoursPerCell.map { TimeInterval.hours(weekdayFewHours * Double($0)) } ?? 0
        return WeekdayPool(
            seconds: total,
            readingCount: tally.readingCount,
            days: days,
            bandShares: shares,
            lowPercent: low.percent,
            lowBelowOnePercent: low.belowOne,
            highPercent: high.percent,
            highBelowOnePercent: high.belowOne,
            mean: tally.mean,
            isFew: total > 0 && total < fewBelow
        )
    }

    /// The heatmap's steps: a value at or above the k-th edge is in step k (0...4; in range diverging at the 70% target,
    /// low and mean more ink for more of the metric). In range and low by their percents as shown
    /// (`WeekdayPool.percent`, `lowPercent`); low's first step is no low at all, so any low time ("<1%" too) is at least
    /// the second ("<2"); the mean as shown (`shownMean`), in mmol/L or mg/dL.
    static func weekdayStepEdges(_ metric: WeekdayMetric, units: GlucoseUnits) -> [Decimal] {
        switch metric {
        case .inRange: return [50, 70, 80, 90]
        case .low: return [1, 2, 4, 8]
        case .mean: return units == .mmolL ? [6, 7, 8, 9] : [110, 130, 150, 170]
        }
    }

    /// A pool's step on the heatmap (`weekdayStepEdges`), nil without data.
    static func weekdayStep(_ pool: WeekdayPool, metric: WeekdayMetric, units: GlucoseUnits) -> Int? {
        guard pool.hasData else { return nil }
        let value: Decimal
        switch metric {
        case .inRange: value = Decimal(pool.percent(.inRange))
        case .low:
            // any low time is at least the first edge: "<1%" is "<2", not "0"
            let hasLow = pool.lowPercent > 0 || pool.lowBelowOnePercent
            value = hasLow ? Decimal(Swift.max(pool.lowPercent, 1)) : 0
        case .mean:
            guard let mean = pool.mean else { return nil }
            value = shownMean(mean, units: units)
        }
        return weekdayStepEdges(metric, units: units).filter { value >= $0 }.count
    }

    /// The hour `offset` rows of `hoursPerRow` on from `hour`'s row, wrapping around midnight: the row's first hour.
    static func weekdayRowStep(_ hour: Int, by offset: Int, hoursPerRow: Int) -> Int {
        let size = Swift.min(Swift.max(hoursPerRow, 1), 24)
        let rows = 24 / size
        let row = ((Swift.min(Swift.max(hour, 0), 23) / size + offset) % rows + rows) % rows
        return row * size
    }

    // MARK: - Helpers

    private static let minutesPerDay = StatsClock.minutesPerDay

    /// The first point whose span ends after `date` (spans never reach past the next reading).
    private static func firstIndex(in w: [WeightedPoint], endingAfter date: Date) -> Int {
        let low = w.partitionIndex { $0.time >= date }
        if low > 0, w[low - 1].end > date {
            return low - 1
        }
        return low
    }

    /// Histograms by local clock time: `bin` maps the minute of the day (0..<1440) to a histogram index.
    private static func clockHistograms(
        _ w: [WeightedPoint],
        calendar: Calendar,
        clippedTo window: DateInterval,
        count: Int,
        bin: (Int) -> Int
    ) -> [GlucoseHistogram] {
        var histograms = Array(repeating: GlucoseHistogram(), count: count)
        var offsets = ZoneOffsets(calendar.timeZone)
        for point in w {
            let seconds = StatsIntervals.overlap(from: point.time, to: point.end, in: window)
            guard seconds > 0 else { continue }
            let startsInside = point.time >= window.start && point.time < window.end
            let minute = StatsClock.minuteOfDay(point.time, secondsFromGMT: offsets.secondsFromGMT(for: point.time))
            let index = Swift.min(Swift.max(bin(minute), 0), count - 1)
            histograms[index].add(point, seconds: seconds, startsInside: startsInside)
        }
        return histograms
    }

    /// Each reading's overlap with each of the days it touches, oldest -> newest: `body` gets the reading, its local
    /// clock minute (0..<1440), the day's index, the seconds inside that day and whether the reading starts in it. A
    /// reading across midnight is given once for each day; readings outside the days are skipped.
    /// - Parameter days: sorted oldest -> newest, not overlapping
    static func forEachOverlap(
        _ w: [WeightedPoint],
        days: [DateInterval],
        calendar: Calendar,
        _ body: (_ point: WeightedPoint, _ minute: Int, _ day: Int, _ seconds: Double, _ startsInside: Bool) -> Void
    ) {
        guard let first = days.first, let last = days.last else { return }
        var offsets = ZoneOffsets(calendar.timeZone)
        // the first day ending after the reading's start
        var current = 0
        var index = firstIndex(in: w, endingAfter: first.start)
        while index < w.count, w[index].time < last.end {
            let point = w[index]
            index += 1
            while current < days.count, days[current].end <= point.time {
                current += 1
            }
            var minute: Int?
            var day = current
            while day < days.count, days[day].start < point.end {
                let seconds = StatsIntervals.overlap(from: point.time, to: point.end, in: days[day])
                if seconds > 0 {
                    let clock = minute
                        ?? StatsClock.minuteOfDay(point.time, secondsFromGMT: offsets.secondsFromGMT(for: point.time))
                    minute = clock
                    body(point, clock, day, seconds, point.time >= days[day].start && point.time < days[day].end)
                }
                day += 1
            }
        }
    }

    /// A zone's offset, kept from the moment it was looked up until the zone's next transition (the offset is the
    /// same in between): `clockHistograms` asks for every reading, oldest -> newest, so a 90-day profile looks it up
    /// a few times instead of for every reading. A moment before the kept one is looked up again.
    private struct ZoneOffsets {
        let timeZone: TimeZone
        private var from: Date?
        /// nil: no transition after `from`
        private var until: Date?
        private var seconds = 0

        init(_ timeZone: TimeZone) {
            self.timeZone = timeZone
        }

        mutating func secondsFromGMT(for date: Date) -> Int {
            if let from, from <= date, until.map({ date < $0 }) ?? true {
                return seconds
            }
            seconds = timeZone.secondsFromGMT(for: date)
            from = date
            until = timeZone.nextDaylightSavingTimeTransition(after: date)
            return seconds
        }
    }
}
