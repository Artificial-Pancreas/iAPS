import Observation
import SwiftUI

// The charts' selections (`Stat.StateModel`'s), shared by the topics.

/// The bin picked on the AGP (`Stat.StateModel.agpSelection`). Observed only by the views that show it, never by the
/// marks.
@MainActor @Observable final class AGPSelection {
    /// 96: `GlucoseStatsEngine.agpBinMinutes` each
    static let binCount = 24 * 60 / GlucoseStatsEngine.agpBinMinutes

    /// from 00:00
    private(set) var bin = 0

    /// called on every pick, also of the one picked (`Stat.StateModel`: the first interaction after midnight reads
    /// again); not observed
    @ObservationIgnored var onPick: (@MainActor() -> Void)?

    func select(_ bin: Int) {
        onPick?()
        guard bin != self.bin else { return }
        self.bin = bin
    }

    /// A minute of the day picked on the chart: its bin.
    func select(minute: Int, on plot: Stat.AGP.Plot) {
        select(GlucoseStatsEngine.agpBin(atMinute: minute, binCount: plot.binCount))
    }

    /// The bin picked, kept inside the plot's bins; nil without bins.
    func bin(on plot: Stat.AGP.Plot) -> Int? {
        guard plot.binCount > 0 else { return nil }
        return Swift.min(Swift.max(bin, 0), plot.binCount - 1)
    }
}

/// The day picked on the Daily view (`Stat.StateModel.dailySelection`). Observed only by the views that show it: a pick
/// re-renders the Daily view, never the screen around it.
@MainActor @Observable final class DailySelection {
    /// the start of the day picked, nil for the day it opens on (`opensOnLastCompleteDay`): today, or yesterday; either
    /// follows midnight
    private(set) var day: Date?
    /// without a pick, yesterday (the last complete day) instead of today: the Insulin and Meals tabs' days, whose today
    /// has a view of its own (the Today period); a constant, not observed
    let opensOnLastCompleteDay: Bool

    /// called on every pick, also of the one picked (`Stat.StateModel`: the first interaction after midnight reads
    /// again); not observed
    @ObservationIgnored var onPick: (@MainActor() -> Void)?

    init(opensOnLastCompleteDay: Bool = false) {
        self.opensOnLastCompleteDay = opensOnLastCompleteDay
    }

    /// The index shown without a pick: the last day, or the one before it (`opensOnLastCompleteDay`, with two days or
    /// more); nil without days.
    func defaultIndex(dayCount: Int) -> Int? {
        guard dayCount > 0 else { return nil }
        return opensOnLastCompleteDay && dayCount > 1 ? dayCount - 2 : dayCount - 1
    }

    func select(_ day: Date?) {
        onPick?()
        guard day != self.day else { return }
        self.day = day
    }
}

extension DailySelection {
    /// A day of a chart of days (a tap, the stepper); the day it opens on (`defaultIndex`: today, or
    /// yesterday) is kept as nil, so it follows midnight.
    func pick(_ index: Int, in days: [DateInterval]) {
        guard days.indices.contains(index) else { return }
        select(index == defaultIndex(dayCount: days.count) ? nil : days[index].start)
    }

    /// The day shown: the one picked, kept inside the days (the nearest of them), the day it opens on without a pick
    /// (`defaultIndex`: today, the last day, or yesterday); nil without days.
    func index(in days: [DateInterval]) -> Int? {
        guard let opening = defaultIndex(dayCount: days.count) else { return nil }
        guard let day else { return opening }
        return GlucoseStatsEngine.dayIndex(containing: day, in: days) ?? opening
    }
}

/// The hour picked on By hour (`Stat.StateModel.hourSelection`). Observed only by the views that show it, never by the
/// marks.
@MainActor @Observable final class HourSelection {
    /// 0...23, by the local clock
    private(set) var hour = 0

    /// called on every pick, also of the one picked (`Stat.StateModel`: the first interaction after midnight reads
    /// again); not observed
    @ObservationIgnored var onPick: (@MainActor() -> Void)?

    func select(_ hour: Int) {
        onPick?()
        let hour = Swift.min(Swift.max(hour, 0), StatsHourBars.hourCount - 1)
        guard hour != self.hour else { return }
        self.hour = hour
    }

    /// A point of the chart's x axis picked: its hour.
    func select(x: Double) {
        select(StatsHourBars.hour(at: x))
    }

    /// The previous or the next hour, around midnight too.
    func step(by offset: Int) {
        select(GlucoseStatsEngine.hourStep(hour, by: offset))
    }
}

/// The reading picked on the Trace chart. Observed only by the views that show it, never by the marks.
@MainActor @Observable final class TraceSelection {
    struct Picked: Equatable {
        let date: Date
        let range: TraceRange
    }

    /// the time picked, with the range it was picked in; nil: the newest reading
    private(set) var picked: Picked?

    func pick(_ date: Date, on plot: Stat.Trace.Plot) {
        picked = Picked(date: date, range: plot.range)
    }

    func clear() {
        picked = nil
    }

    /// The time picked, nil (the newest reading) when it was picked in another range or is outside the plot's domain
    /// (in the 24 h, a time that slid out of it): a new day or range shows its newest reading from its first frame.
    func date(on plot: Stat.Trace.Plot) -> Date? {
        guard let picked, picked.range == plot.range, plot.domain.contains(picked.date) else { return nil }
        return picked.date
    }
}

/// The cell picked on By weekday's heatmap and the metric shown (`Stat.StateModel.weekdaySelection`). Observed only by
/// the views that show them, never by the cells.
@MainActor @Observable final class WeekdaySelection {
    /// the picked cell's `Calendar` weekday; nil: none picked (no readout)
    private(set) var weekday: Int?
    /// its clock hour, 0...23; a 3-hour block is the block of it
    private(set) var hour = 0
    private(set) var metric: WeekdayMetric = .inRange

    /// called on every pick, also of the one picked (`Stat.StateModel`: the first interaction after midnight reads
    /// again); not observed
    @ObservationIgnored var onPick: (@MainActor() -> Void)?

    func select(weekday: Int, hour: Int) {
        onPick?()
        let hour = Swift.min(Swift.max(hour, 0), 23)
        if weekday != self.weekday {
            self.weekday = weekday
        }
        if hour != self.hour {
            self.hour = hour
        }
    }

    /// The previous or the next row (an hour, or a 3-hour block), around midnight too, on the picked weekday.
    func step(by rows: Int, hoursPerRow: Int) {
        guard let weekday else { return }
        select(weekday: weekday, hour: GlucoseStatsEngine.weekdayRowStep(hour, by: rows, hoursPerRow: hoursPerRow))
    }

    func select(metric: WeekdayMetric) {
        onPick?()
        guard metric != self.metric else { return }
        self.metric = metric
    }

    /// No cell picked: the screen's own reset (entering the view), not a pick.
    func clear() {
        if weekday != nil {
            weekday = nil
        }
    }
}
