import Foundation

// MARK: - Clock

/// The statistics' calendar days and local clock times.
enum StatsClock {
    static let minutesPerDay = 24 * 60

    /// The local clock minute of the day (0..<1440), from the zone's offset at that moment: the repeated hour of a
    /// DST change maps to its clock time twice, the skipped one never.
    static func minuteOfDay(_ date: Date, in timeZone: TimeZone) -> Int {
        minuteOfDay(date, secondsFromGMT: timeZone.secondsFromGMT(for: date))
    }

    /// `minuteOfDay(_:in:)` with the zone's offset at that moment.
    static func minuteOfDay(_ date: Date, secondsFromGMT: Int) -> Int {
        let local = date.timeIntervalSince1970 + TimeInterval(secondsFromGMT)
        let secondsPerDay = TimeInterval.hours(24)
        let secondOfDay = local - (local / secondsPerDay).rounded(.down) * secondsPerDay
        return Swift.min(Swift.max(Int(secondOfDay / 60), 0), minutesPerDay - 1)
    }

    /// The local clock hour (0...23) of a moment, from the zone's offset then: the repeated hour of a DST change is the
    /// same hour twice.
    static func clockHour(_ date: Date, in timeZone: TimeZone) -> Int {
        minuteOfDay(date, in: timeZone) / 60
    }

    /// The zone's offsets during a calendar day, its end included (where the next day's 00:00 is): the one at its
    /// start and after each transition in it, each once.
    static func zoneOffsets(in day: DateInterval, timeZone: TimeZone) -> [Int] {
        var offsets = [timeZone.secondsFromGMT(for: day.start)]
        var from = day.start
        while let transition = timeZone.nextDaylightSavingTimeTransition(after: from), transition <= day.end {
            offsets.append(timeZone.secondsFromGMT(for: transition))
            from = transition
        }
        offsets.append(timeZone.secondsFromGMT(for: day.end))
        var seen = Set<Int>()
        return offsets.filter { seen.insert($0).inserted }
    }

    /// A calendar day's local clock, worked out once for the moments showing many clock minutes.
    struct ClockDay {
        let day: DateInterval
        let timeZone: TimeZone
        /// the day's local midnight, in local seconds (a midnight the zone skips: the day starts later, same day)
        private let midnight: TimeInterval
        /// `zoneOffsets(in: day, ...)`
        private let offsets: [Int]

        init(_ day: DateInterval, timeZone: TimeZone) {
            self.day = day
            self.timeZone = timeZone
            let secondsPerDay = TimeInterval.hours(24)
            let local = day.start.timeIntervalSince1970 + TimeInterval(timeZone.secondsFromGMT(for: day.start))
            midnight = (local / secondsPerDay).rounded(.down) * secondsPerDay
            offsets = StatsClock.zoneOffsets(in: day, timeZone: timeZone)
        }

        /// The moments in `[day.start, day.end)`, or `[day.start, day.end]` with `throughEnd`, whose local clock shows
        /// the minute of the day: one, two in a repeated hour, none in a skipped one.
        func times(minute: Int, throughEnd: Bool = false) -> [Date] {
            var times: [Date] = []
            for offset in offsets {
                let time = Date(timeIntervalSince1970: midnight + .minutes(minute) - TimeInterval(offset))
                let beforeEnd = throughEnd ? time <= day.end : time < day.end
                guard day.start <= time, beforeEnd, timeZone.secondsFromGMT(for: time) == offset else { continue }
                times.append(time)
            }
            return times
        }
    }

    /// The start of the calendar day after the date's.
    static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: startOfDay).map { calendar.startOfDay(for: $0) }
            ?? startOfDay.addingTimeInterval(.hours(24))
    }

    /// The whole calendar days (23, 24 or 25 h) touching the interval, oldest -> newest; at least the day of its start.
    static func calendarDays(in interval: DateInterval, calendar: Calendar) -> [DateInterval] {
        var days: [DateInterval] = []
        var dayStart = calendar.startOfDay(for: interval.start)
        repeat {
            let next = endOfDay(dayStart, calendar: calendar)
            guard next > dayStart else { break }
            days.append(DateInterval(start: dayStart, end: next))
            dayStart = next
        } while dayStart < interval.end
        return days
    }

    /// The whole calendar day (23, 24 or 25 h) of the date.
    static func wholeDay(of date: Date, calendar: Calendar) -> DateInterval {
        calendarDays(in: DateInterval(start: date, duration: 0), calendar: calendar).first
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: .hours(24))
    }

    /// The start of the calendar day `days` days before `today`'s (`today` a start of day); nil when the calendar
    /// can't tell.
    static func dayStart(_ days: Int, before today: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: -days, to: today).map { calendar.startOfDay(for: $0) }
    }

    /// The calendar, frozen: an autoupdating one could change its time zone halfway through a request.
    static func frozen(_ calendar: Calendar) -> Calendar {
        var frozen = Calendar(identifier: calendar.identifier)
        frozen.locale = calendar.locale
        frozen.firstWeekday = calendar.firstWeekday
        frozen.minimumDaysInFirstWeek = calendar.minimumDaysInFirstWeek
        frozen.timeZone = TimeZone(identifier: calendar.timeZone.identifier) ?? calendar.timeZone
        return frozen
    }
}

/// A calendar day as a cache key: its date in the calendar (`StatsCalendarIdentity`) of the cache.
struct StatsDayKey: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, _ calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    static func < (lhs: StatsDayKey, rhs: StatsDayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// What the cached days' dates mean: the calendar and its time zone.
struct StatsCalendarIdentity: Equatable, Sendable {
    let calendar: Calendar.Identifier
    let timeZone: String

    init(_ calendar: Calendar) {
        self.calendar = calendar.identifier
        timeZone = calendar.timeZone.identifier
    }
}

// MARK: - Intervals

/// The statistics' interval arithmetic.
enum StatsIntervals {
    /// Overlapping or touching intervals as one, sorted oldest first; empty ones dropped.
    static func mergedDroppingEmpty(_ intervals: [DateInterval]) -> [DateInterval] {
        mergedKeepingEmpty(intervals.filter { $0.duration > 0 })
    }

    /// Closed intervals sorted, overlapping or touching ones merged; zero-length ones kept.
    static func mergedKeepingEmpty(_ intervals: [DateInterval]) -> [DateInterval] {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: Swift.max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    /// The parts of the intervals inside `span`; empty parts dropped.
    static func intersect(_ intervals: [DateInterval], with span: DateInterval) -> [DateInterval] {
        intervals.compactMap { interval in
            let start = Swift.max(interval.start, span.start)
            let end = Swift.min(interval.end, span.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }
    }

    /// The part of `interval` inside the window, nil when they don't overlap (a zero-length part where they touch).
    static func clipped(_ interval: DateInterval, to window: DateInterval) -> DateInterval? {
        let start = Swift.max(interval.start, window.start)
        let end = Swift.min(interval.end, window.end)
        return start <= end ? DateInterval(start: start, end: end) : nil
    }

    /// The intervals without the parts in `removed`, oldest first; empty parts dropped.
    static func subtract(_ intervals: [DateInterval], _ removed: [DateInterval]) -> [DateInterval] {
        var remaining = intervals.filter { $0.duration > 0 }
        for cut in removed where cut.duration > 0 {
            remaining = remaining.flatMap { interval -> [DateInterval] in
                guard cut.end > interval.start, interval.end > cut.start else { return [interval] }
                var parts: [DateInterval] = []
                if cut.start > interval.start {
                    parts.append(DateInterval(start: interval.start, end: cut.start))
                }
                if interval.end > cut.end {
                    parts.append(DateInterval(start: cut.end, end: interval.end))
                }
                return parts
            }
        }
        return remaining.sorted { $0.start < $1.start }
    }

    /// The seconds the two intervals share.
    static func overlap(_ a: DateInterval, _ b: DateInterval) -> TimeInterval {
        overlap(from: a.start, to: a.end, in: b)
    }

    /// The seconds of `[start, end)` inside the window.
    static func overlap(from start: Date, to end: Date, in window: DateInterval) -> TimeInterval {
        Swift.max(Swift.min(end, window.end).timeIntervalSince(Swift.max(start, window.start)), 0)
    }

    /// Consecutive indices grouped into runs (`[0, 1, 3]` -> `[[0, 1], [3]]`): the days or sessions read together.
    static func runs(_ indices: [Int]) -> [[Int]] {
        var runs: [[Int]] = []
        for index in indices {
            if let last = runs.last?.last, last + 1 == index {
                runs[runs.count - 1].append(index)
            } else {
                runs.append([index])
            }
        }
        return runs
    }
}

extension RandomAccessCollection {
    /// The first index whose element satisfies `isAfter` (false up to some index, true from there on), by binary
    /// search; `endIndex` if none.
    func partitionIndex(where isAfter: (Element) throws -> Bool) rethrows -> Index {
        var low = startIndex
        var high = endIndex
        while low < high {
            let middle = index(low, offsetBy: distance(from: low, to: high) / 2)
            if try isAfter(self[middle]) {
                high = middle
            } else {
                low = index(after: middle)
            }
        }
        return low
    }
}

// MARK: - Basal schedules

/// The oldest basal schedule record, which the time before it uses ("Profile assumed"): by its date and its schedule
/// (a Nightscout re-import can change the entries of a record in place, signalled only from its date on). Keys the
/// Insulin tab's cached "Profile assumed" days and the Patches topic's kept sessions.
struct AssumedSchedule: Equatable, Sendable {
    let date: Date
    let fingerprint: String

    /// The oldest record with entries, when it is after `start` (so time before it can be assumed); nil otherwise.
    static func oldest(_ schedules: [BasalScheduleRecordValue], after start: Date) -> AssumedSchedule? {
        guard let oldest = schedules.filter(\.entries.isNotEmpty).min(by: { $0.date < $1.date }), oldest.date > start
        else { return nil }
        return AssumedSchedule(date: oldest.date, fingerprint: BasalScheduleRecordValue.fingerprint(oldest.entries))
    }
}
