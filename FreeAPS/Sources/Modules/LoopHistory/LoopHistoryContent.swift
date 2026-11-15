import Foundation

extension LoopHistory {
    /// A day's colour on the heat-map, by its share of the loops due that ran, as shown (`of(shown:)`).
    enum Bin: Int, Sendable, CaseIterable {
        /// 95 % or more
        case best
        /// 90 % or more
        case good
        /// 75 % or more
        case fair
        /// under 75 %
        case poor

        static func of(_ percent: Double) -> Bin {
            if percent >= 95 { return .best }
            if percent >= 90 { return .good }
            if percent >= 75 { return .fair }
            return .poor
        }

        /// The bin of the percent as it is shown (`HomeLoopsCard.Content.percent`): 94.96, shown "95.0", is the best.
        static func of(shown percent: Double) -> Bin {
            of(HomeLoopsCard.Content.shownPercent(percent))
        }
    }

    /// What the screen shows, formatted once per read or pick (`make`): pure, off any clock (now is the history's end).
    struct Content: Equatable, Sendable {
        /// "29 Sep – 30 Oct": the calendar's first day to today
        let calendarDates: String
        /// the weekdays' initials, from the calendar's first weekday on
        let weekdays: [String]
        /// `Config.weeks` rows of 7 days, this week last
        let weeks: [[Cell]]
        let detail: Detail
        /// the selection shown: a day outside the calendar's days is the last 30 days
        let selection: Selection
    }

    /// A day of the calendar.
    struct Cell: Equatable, Sendable, Identifiable {
        /// the day's start
        let id: Date
        /// "27"
        let number: String
        /// "Today", or the month ("Oct") on its first day and the calendar's first cell
        let caption: String?
        let isToday: Bool
        /// after today: the number only, not a button
        let isFuture: Bool
        /// nil without readings a loop could run on (an outlined cell)
        let bin: Bin?
        let isSelected: Bool
    }

    /// The last 30 days, or the day picked.
    struct Detail: Equatable, Sendable {
        /// "Last 30 days", "Today", "Tuesday 27 October"
        let title: String
        /// "1 Oct – 30 Oct, today so far", "So far, until 14:35", "The whole day"
        let subtitle: String
        let isDay: Bool
        /// "97.3", "100", "–"
        let percent: String
        let hasPercent: Bool
        /// "8,123 of 8,350 loops · 271 a day" (no "a day" on a day): the slots that succeeded, of the slots
        let counts: String
        let failed: String
        let missed: String
        /// "3.1" (seconds), "–" without loops
        let medianDuration: String
        /// "Through the day", "By time of day, all 30 days"
        let stripTitle: String
        /// a column per half hour, fractions of the strip
        let columns: [LoopStripColumns.Column]
        /// the day's gaps of 15 min or more (none on the 30 days)
        let gapMarks: [LoopStripGapMarks.Mark]
        /// the strip's hours: 00, 06, 12, 18, 24 in the locale's clock
        let axis: [String]
        let gaps: [GapRow]
        let causes: [CauseRow]
        /// "12 loops missed or failed"; nil when every loop due ran
        let causesLine: String?
    }

    /// One of the longest gaps.
    struct GapRow: Equatable, Sendable, Identifiable {
        /// the gap's start
        let id: Date
        /// "Tue 27 Oct" on the 30 days (a tap shows the day); nil on a day
        let day: String?
        /// the day it shows
        let dayStart: Date
        /// "13:10–16:40 · no loop ran"
        let times: String
        /// "3 h 30 min"
        let length: String
    }

    /// A cause of the loops due that didn't run.
    struct CauseRow: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            /// failed loops, of the type (its symbol and colour)
            case failure(LoopEventType)
            /// the causes after the first `Config.causesShown`
            case other
            /// no loop started
            case missed
        }

        let id: String
        let kind: Kind
        /// "Pump busy", or the text of a failure of no known kind
        let title: String
        /// the most frequent text ("and 2 more"); nil when the title is the text
        let message: String?
        /// "12"
        let count: String
        /// of the loops due that didn't run
        let fraction: Double
    }
}

extension LoopHistory.Content {
    typealias Day = HomeLoopStats.Day
    typealias Selection = LoopHistory.Selection

    /// The screen for the history (now is its end) and the selection.
    static func make(_ history: HomeLoopsStore.History, selection: Selection, calendar: Calendar) -> LoopHistory.Content {
        let now = history.window.end
        let formats = Formats(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let byStart = Dictionary(history.days.map { ($0.day.start, $0) }, uniquingKeysWith: { _, newest in newest })

        let firstCell = firstCalendarDay(today: today, calendar: calendar)
        let cellDays = (0 ..< LoopHistory.Config.weeks * 7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstCell).map { calendar.startOfDay(for: $0) }
        }
        // a day outside the calendar (midnight moved it out), or not yet: the 30 days
        let shown: Selection
        if case let .day(start) = selection, start <= today, cellDays.contains(start) {
            shown = selection
        } else {
            shown = .lastDays
        }

        let cells = cellDays.enumerated().map { index, start in
            cell(
                start,
                day: byStart[start],
                isFirst: index == 0,
                today: today,
                selected: shown == .day(start),
                formats: formats,
                calendar: calendar
            )
        }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< min($0 + 7, cells.count)]) }

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0 ..< 7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }

        let gaps = HomeLoopStats.gaps(of: history.days, previousStart: history.previousStart, end: now)
        let counted = gaps.marked + (gaps.ongoing.map { [$0] } ?? [])
        let detail = self.detail(
            shown,
            days: history.days,
            gaps: counted,
            today: today,
            now: now,
            formats: formats,
            calendar: calendar
        )
        return LoopHistory.Content(
            calendarDates: formats.shortDay(firstCell) + " – " + formats.shortDay(today),
            weekdays: weekdays,
            weeks: weeks,
            detail: detail,
            selection: shown
        )
    }

    /// The calendar's first day: the first weekday of the week `Config.weeks - 1` weeks before today's.
    static func firstCalendarDay(today: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: today)
        let intoWeek = (weekday - calendar.firstWeekday + 7) % 7
        let back = intoWeek + (LoopHistory.Config.weeks - 1) * 7
        return calendar.date(byAdding: .day, value: -back, to: today).map { calendar.startOfDay(for: $0) } ?? today
    }

    // MARK: - Calendar

    private static func cell(
        _ start: Date,
        day: Day?,
        isFirst: Bool,
        today: Date,
        selected: Bool,
        formats: Formats,
        calendar: Calendar
    ) -> LoopHistory.Cell {
        let isToday = start == today
        let isFuture = start > today
        let caption: String? = isToday
            ? NSLocalizedString("Today", comment: "")
            : (isFirst || calendar.component(.day, from: start) == 1) ? formats.month(start) : nil
        let percent = (day?.slots ?? HomeLoopStats.Slots()).percent
        return LoopHistory.Cell(
            id: start,
            number: formats.dayNumber(start),
            caption: caption,
            isToday: isToday,
            isFuture: isFuture,
            bin: percent.map { LoopHistory.Bin.of(shown: $0) },
            isSelected: selected
        )
    }

    // MARK: - Detail

    private static func detail(
        _ selection: Selection,
        days: [Day],
        gaps: [HomeLoopStats.CountedGap],
        today: Date,
        now: Date,
        formats: Formats,
        calendar: Calendar
    ) -> LoopHistory.Detail {
        let scope: DateInterval
        let title: String
        let subtitle: String
        let isDay: Bool
        switch selection {
        case let .day(start):
            let end = calendar.date(byAdding: .day, value: 1, to: start).map { calendar.startOfDay(for: $0) } ?? now
            scope = DateInterval(start: start, end: max(start, min(end, now)))
            isDay = true
            if start == today {
                title = NSLocalizedString("Today", comment: "")
                subtitle = String(
                    format: NSLocalizedString("So far, until %@", comment: "Loops screen: today up to the read's time"),
                    formats.time(now)
                )
            } else {
                title = formats.longDay(start)
                subtitle = NSLocalizedString("The whole day", comment: "Loops screen: a past day")
            }
        case .lastDays:
            let start = calendar.date(byAdding: .day, value: -(LoopHistory.Config.aggregateDays - 1), to: today)
                .map { calendar.startOfDay(for: $0) } ?? today
            scope = DateInterval(start: start, end: max(start, now))
            isDay = false
            title = String(
                format: NSLocalizedString("Last %d days", comment: "Loops screen: the detail without a day picked"),
                LoopHistory.Config.aggregateDays
            )
            subtitle = String(
                format: NSLocalizedString(
                    "%1$@ – %2$@, today so far",
                    comment: "Loops screen: the first of the last 30 days, today"
                ),
                formats.shortDay(start),
                formats.shortDay(today)
            )
        }
        let inScope = isDay ? days.filter { $0.day.start == scope.start } : days.filter { $0.day.start >= scope.start }
        // the strip's times: of the day's equal parts (its columns), on a DST day not whole hours after midnight
        let stripDay = self.stripDay(selection, today: today, calendar: calendar)
        let partTime = { (part: Int) in
            stripDay.start.addingTimeInterval(stripDay.duration * Double(part) / Double(HomeLoopStats.Config.dayParts))
        }
        let slots = inScope.reduce(HomeLoopStats.Slots()) { $0 + $1.slots }
        var causes: [LoopFailureCause: Int] = [:]
        var durations: [Int: Int] = [:]
        var partSlots = Array(repeating: 0, count: HomeLoopStats.Config.dayParts)
        var partSuccesses = partSlots
        for day in inScope {
            causes.merge(day.causes, uniquingKeysWith: +)
            durations.merge(day.durations, uniquingKeysWith: +)
            for part in partSlots.indices {
                partSlots[part] += day.partSlots[part]
                partSuccesses[part] += day.partSuccesses[part]
            }
        }

        let percent = slots.percent
        var counts = HomeLoopsCard.Content.loops(slots.successes, of: slots.count)
        if !isDay {
            let dayCount = inScope.reduce(0) { $0 + $1.interval.duration } / .days(1)
            if dayCount > 0 {
                counts += " · " + String(
                    format: NSLocalizedString("%@ a day", comment: "Loops screen: loops per day (\"271 a day\")"),
                    Int((Double(slots.successes) / dayCount).rounded()).formatted()
                )
            }
        }

        let columns = (0 ..< HomeLoopStats.Config.dayParts).compactMap { part -> LoopStripColumns.Column? in
            guard partSlots[part] > 0 else { return nil }
            let width = 1 / Double(HomeLoopStats.Config.dayParts)
            return LoopStripColumns.Column(
                x: Double(part) * width,
                width: width,
                height: Double(partSuccesses[part]) / Double(partSlots[part])
            )
        }
        let scopeGaps = gaps.filter { gap in
            let end = gap.gap.ongoing ? now : gap.gap.end
            return gap.gap.start < scope.end && scope.start < end
        }
        let gapMarks: [LoopStripGapMarks.Mark] = isDay && scope.duration > 0 && stripDay.duration > 0
            ? scopeGaps.map { gap in
                let position = { (date: Date) in
                    min(max(date.timeIntervalSince(stripDay.start) / stripDay.duration, 0), 1)
                }
                return LoopStripGapMarks.Mark(
                    start: position(gap.gap.start.addingTimeInterval(gap.gap.loopInterval)),
                    end: position(gap.gap.ongoing ? now : gap.gap.end)
                )
            }
            : []

        // the start, the quarters and the end of the strip
        let quarter = HomeLoopStats.Config.dayParts / 4
        let axis = (0 ... 4).map { formats.hour(partTime($0 * quarter)) }

        let failedAndMissed = slots.failed + slots.missed
        return LoopHistory.Detail(
            title: title,
            subtitle: subtitle,
            isDay: isDay,
            percent: percent.map(HomeLoopsCard.Content.percent) ?? "–",
            hasPercent: percent != nil,
            counts: counts,
            failed: slots.failed.formatted(),
            missed: slots.missed.formatted(),
            medianDuration: HomeLoopStats.medianDuration(durations)
                .map { $0.formatted(.number.precision(.fractionLength(1)).grouping(.never)) } ?? "–",
            stripTitle: isDay
                ? NSLocalizedString("Through the day", comment: "Loops screen: the strip of a day")
                : String(
                    format: NSLocalizedString("By time of day, all %d days", comment: "Loops screen: the strip of the 30 days"),
                    LoopHistory.Config.aggregateDays
                ),
            columns: columns,
            gapMarks: gapMarks,
            axis: axis,
            gaps: gapRows(scopeGaps, isDay: isDay, formats: formats, calendar: calendar),
            causes: causeRows(causes, missed: slots.missed, total: failedAndMissed),
            causesLine: failedAndMissed > 0
                ? String(
                    format: NSLocalizedString(
                        "%@ missed or failed",
                        comment: "Loops screen: the loops due that didn't run (\"12 loops\")"
                    ),
                    HomeLoopsCard.Content.loops(failedAndMissed)
                )
                : nil
        )
    }

    /// The day whose equal parts the strip's columns are (`HomeLoopStats.Day.partSlots`): the day picked; for the 30
    /// days, pooled by part, a day of 24 hours (today, or the day before on a DST day), whose parts are the clock's half
    /// hours.
    static func stripDay(_ selection: Selection, today: Date, calendar: Calendar) -> DateInterval {
        let whole = { (start: Date) in
            let end = calendar.date(byAdding: .day, value: 1, to: start).map { calendar.startOfDay(for: $0) }
                ?? start.addingTimeInterval(.days(1))
            return DateInterval(start: start, end: max(start, end))
        }
        switch selection {
        case let .day(start):
            return whole(start)
        case .lastDays:
            let todays = whole(today)
            guard todays.duration != .days(1),
                  let before = calendar.date(byAdding: .day, value: -1, to: today).map({ calendar.startOfDay(for: $0) })
            else { return todays }
            return whole(before)
        }
    }

    // MARK: - Gaps

    /// The longest `Config.gapsShown`, the longest first.
    static func gapRows(
        _ gaps: [HomeLoopStats.CountedGap],
        isDay: Bool,
        formats: Formats,
        calendar: Calendar
    ) -> [LoopHistory.GapRow] {
        gaps.sorted { $0.gap.duration > $1.gap.duration }.prefix(LoopHistory.Config.gapsShown).map { counted in
            let gap = counted.gap
            // a day or longer: the times with their days ("Mon 23:55 – Wed 00:00"), the clock alone would read as hours
            let dated = gap.duration >= .days(1) && !calendar.isDate(gap.end, inSameDayAs: gap.start)
            let time = { (date: Date) in dated ? formats.weekdayTime(date) : formats.time(date) }
            let start = time(gap.start)
            let end = gap.ongoing ? NSLocalizedString("now", comment: "Loops screen: an ongoing gap's end") : time(gap.end)
            let why = counted.lacksReadings
                ? NSLocalizedString("no CGM readings", comment: "Loops screen: why a gap: the CGM sent no readings")
                : NSLocalizedString("no loop ran", comment: "Loops screen: no loop started")
            let times = start + (dated ? " – " : "–") + end + " · " + why
            return LoopHistory.GapRow(
                id: gap.start,
                day: isDay ? nil : formats.shortWeekdayDay(gap.start),
                dayStart: calendar.startOfDay(for: gap.start),
                times: times,
                length: HomeLoopsCard.duration(gap.duration)
            )
        }
    }

    // MARK: - Causes

    /// The failed loops (slots) by cause, grouped by the loop event type (a text of no known kind on its own), the first
    /// `Config.causesShown` and the rest as "Other", and the loops due that didn't start ("No loop ran"); the most
    /// first, "Other" last.
    static func causeRows(_ causes: [LoopFailureCause: Int], missed: Int, total: Int) -> [LoopHistory.CauseRow] {
        struct Group {
            let id: String
            let type: LoopEventType
            let title: String
            var count = 0
            var messages: [String: Int] = [:]
            let ungrouped: Bool
        }
        var groups: [String: Group] = [:]
        for (cause, count) in causes {
            let id = cause.isUngrouped ? "text:" + cause.message.lowercased() : "type:" + cause.type.rawValue
            var group = groups[id] ?? Group(id: id, type: cause.type, title: cause.title, ungrouped: cause.isUngrouped)
            group.count += count
            group.messages[cause.message, default: 0] += count
            groups[id] = group
        }
        let sorted = groups.values.sorted { $0.count != $1.count ? $0.count > $1.count : $0.title < $1.title }
        let fraction = { (count: Int) in total > 0 ? Double(count) / Double(total) : 0 }

        var rows: [(row: LoopHistory.CauseRow, count: Int)] = sorted.prefix(LoopHistory.Config.causesShown).map { group in
            let message: String? = group.ungrouped ? nil : {
                let ordered = group.messages.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                guard let first = ordered.first?.key else { return nil }
                guard ordered.count > 1 else { return first }
                return String(
                    format: NSLocalizedString("%1$@ (and %2$d more)", comment: "Loops screen: a cause's most frequent text"),
                    first,
                    ordered.count - 1
                )
            }()
            let row = LoopHistory.CauseRow(
                id: group.id,
                kind: .failure(group.type),
                title: group.title,
                message: message,
                count: group.count.formatted(),
                fraction: fraction(group.count)
            )
            return (row, group.count)
        }
        if missed > 0 {
            let title = NSLocalizedString("No loop ran", comment: "Loops screen: the loops due that didn't start")
            let message = NSLocalizedString(
                "No loop started when one was due",
                comment: "Loops screen: the loops due that didn't start"
            )
            let row = LoopHistory.CauseRow(
                id: "missed",
                kind: .missed,
                title: title,
                message: message,
                count: missed.formatted(),
                fraction: fraction(missed)
            )
            // after the failures of as many
            let index = rows.firstIndex { $0.count < missed } ?? rows.count
            rows.insert((row, missed), at: index)
        }
        let rest = sorted.dropFirst(LoopHistory.Config.causesShown)
        if !rest.isEmpty {
            let count = rest.reduce(0) { $0 + $1.count }
            rows.append((LoopHistory.CauseRow(
                id: "other",
                kind: .other,
                title: NSLocalizedString("Other", comment: "Loops screen: the other causes"),
                message: rest.map(\.title).joined(separator: ", "),
                count: count.formatted(),
                fraction: fraction(count)
            ), count))
        }
        return rows.map(\.row)
    }

    // MARK: - Formats

    /// The dates and times in the calendar's locale, time zone and clock (12 or 24 hours).
    struct Formats {
        let calendar: Calendar

        private var style: Date.FormatStyle {
            Date.FormatStyle(
                locale: calendar.locale ?? .current,
                calendar: calendar,
                timeZone: calendar.timeZone
            )
        }

        /// "29 Sep"
        func shortDay(_ date: Date) -> String {
            date.formatted(style.day().month(.abbreviated))
        }

        /// "Tue 27 Oct"
        func shortWeekdayDay(_ date: Date) -> String {
            date.formatted(style.weekday(.abbreviated).day().month(.abbreviated))
        }

        /// "Tuesday 27 October"
        func longDay(_ date: Date) -> String {
            date.formatted(style.weekday(.wide).day().month(.wide))
        }

        /// "Oct"
        func month(_ date: Date) -> String {
            date.formatted(style.month(.abbreviated))
        }

        /// "27"
        func dayNumber(_ date: Date) -> String {
            date.formatted(style.day())
        }

        /// "14:35", "2:35 PM"
        func time(_ date: Date) -> String {
            date.formatted(style.hour().minute())
        }

        /// "06", "6 AM"
        func hour(_ date: Date) -> String {
            date.formatted(style.hour())
        }

        /// "Mon 23:55", "Mon 11:55 PM"
        func weekdayTime(_ date: Date) -> String {
            date.formatted(style.weekday(.abbreviated)) + " " + time(date)
        }
    }
}
