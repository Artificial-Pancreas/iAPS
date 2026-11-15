import Foundation
import Observation
import SwiftUI

/// Good & bad days' picks (`Stat.StateModel.goodBadDaysSelection`): the time picked on the chart and the day lists
/// open. Observed only by the views that show them; no request carries them, so a pick never reads.
@MainActor @Observable final class GoodBadDaysSelection {
    /// A group: the reference (the best third) or the one compared with it (the worst third).
    enum Side: Hashable, Sendable {
        case reference
        case compared
    }

    /// the bin picked (`GlucoseStatsEngine.agpBinMinutes` each, from 00:00); nil: the main stretch
    /// (`Stat.GoodBadDays.Content.openingBin`)
    private(set) var bin: Int?
    /// the groups whose days are listed, in place
    private(set) var open: Set<Side> = []

    /// called on every pick, also of the one picked (`Stat.StateModel`: the first interaction after midnight reads
    /// again); not observed
    @ObservationIgnored var onPick: (@MainActor() -> Void)?

    func select(bin: Int) {
        onPick?()
        guard bin != self.bin else { return }
        self.bin = bin
    }

    /// A group's days listed, or folded again.
    func toggle(_ side: Side) {
        onPick?()
        if open.contains(side) {
            open.remove(side)
        } else {
            open.insert(side)
        }
    }

    /// The screen's own reset (another period: its main stretch), not a pick.
    func showMainStretch() {
        bin = nil
    }

    /// The bin shown: the one picked, the opening one without a pick.
    func bin(opening: Int) -> Int {
        bin ?? opening
    }
}

extension Stat {
    /// Good & bad days, formatted for display from the provider's result (`GoodBadDaysData`): the best third against
    /// the worst. Only strings and the plot's pieces are built here.
    struct GoodBadDays: Equatable {
        typealias Side = GoodBadDaysSelection.Side

        /// What the chart draws besides its groups: the AGP's frame (`AGPFrameMarks`), its axes, and
        /// each bin's times.
        struct Plot: Equatable, Sendable {
            /// mg/dL, one axis for every group (`GoodBadDaysResult.axis`)
            let axis: ClosedRange<Int>
            /// the in-range band's edges, solid
            let low: Int
            let high: Int
            /// 54, 180 (mmol: 181) and 250 inside the axis, dashed; not where a range edge is
            let dashed: [Int]
            /// the local 00/06/12/18
            let xTicks: [AGP.Plot.Tick]
            let yLabels: [AGP.Plot.Level]
            /// by bin: "08:30–08:45"
            let binTimes: [String]
            /// by bin: "08:30"
            let binStarts: [String]
            let unit: String

            var edges: [Int] { low == high ? [low] : [low, high] }

            var binCount: Int { binTimes.count }

            /// where a bin is drawn: its middle minute
            func minute(ofBin bin: Int) -> Int {
                GlucoseStatsEngine.agpMiddleMinute(ofBin: bin, binCount: binCount)
            }
        }

        /// A group: its profile, its readouts and its days.
        struct Group: Equatable {
            let side: Side
            /// "Best third"
            let name: String
            /// "Best": the tables' columns
            let short: String
            /// "the best third": "lower on the best third"
            let onName: String
            let dayCount: Int
            /// enough days for its band and its rows
            let isShown: Bool
            /// the 25–75% band and the median; empty when it isn't shown
            let points: [AGPPlotPoint]
            /// by bin: the 25th percentile, the median and the 75th, formatted; nil without data
            let readouts: [[String]?]
            /// by bin: the median as drawn (kept inside the axis), mg/dL; nil without data
            let plottedMedians: [Double?]
            /// newest first
            let days: [Day]
            /// "Best third (10)"
            let title: String
            /// its first and last day ("1 Oct – 29 Oct"), "None" without days
            let span: String
        }

        /// A day of a group's list: it opens on the Day tab.
        struct Day: Equatable, Identifiable {
            /// the day's start
            let id: Date
            /// "Mon 27 Oct"
            let title: String
            /// "in range 81%"
            let detail: String
            /// its bands (the Statistics range), the day's bar
            let segments: [BandSegment]
            /// "GRI 34 · B"
            let gri: String
        }

        /// A row of the glucose card: both groups' median and IQR, and the difference.
        struct GlucoseRow: Equatable, Identifiable {
            struct Cell: Equatable {
                /// the median
                let value: String
                /// "(12–24)"
                let range: String
            }

            let id: GoodBadDaysResult.GlucoseRowID
            let name: String
            /// its range or unit ("3.9–10.0", "mmol/L"); nil without one
            let detail: String?
            let reference: Cell
            let compared: Cell
            /// compared − reference: "+12", "−0.8 pt"
            let difference: String
        }

        /// A row of "What was different on those days": the name, both groups' values in one line, the difference.
        struct FactorRow: Equatable, Identifiable {
            let id: GoodBadFactor
            let name: String
            /// "Best 142 g (120–160) · Worst 188 g (150–210) · n 10 / 9", "Best 4 of 10 days · Worst 5 of 5 days"
            let values: String
            /// compared − reference as shown: "+46 g", "−25 m", "+12 pt"
            let difference: String
            /// "more", "less", "later", "earlier", "the same"
            let direction: String
            /// what the row counts; nil without a note
            let note: String?
        }

        /// A group of factor rows, in their fixed order.
        struct FactorSection: Equatable, Identifiable {
            let id: GoodBadFactor.Section
            let title: String
            /// under the title (the loop rows' "These follow glucose"); nil without one
            let note: String?
            /// some of its data couldn't be read; nil when all of it was
            let unavailable: String?
            /// the rows with 5 days with a value in each group
            let rows: [FactorRow]
        }

        /// In place of the comparison when the thirds have too few days.
        struct Message: Equatable {
            let title: String
            let detail: String
        }

        /// The comparison, ready to show.
        struct Content: Equatable {
            /// "10 best · 10 worst · 10 in between"
            let counts: String
            /// the thirds' ranges, the days left out
            let lines: [String]
            let reference: Group
            let compared: Group
            /// both groups shown: the chart overlays both, the rows show
            let isComparable: Bool
            /// a shown group under `GoodBadDaysEngine.unlimitedDays` days: marked
            let isLimited: Bool
            /// "Medians differ most 15:00–19:00: 112 vs 186 mg/dL"; nil unless comparable
            let caption: String?
            /// in place of the comparison; nil when comparable
            let message: Message?
            /// the stretches where the medians differ most, in minutes of the day, split at midnight
            let highlights: [Range<Int>]
            /// the bin the time opens on: the main stretch's middle hour, or the clock time now without one
            let openingBin: Int
            /// in their fixed order; none unless comparable
            let glucoseRows: [GlucoseRow]
            /// "Each row: both groups' median and middle half, then how …"
            let factorIntro: String
            /// in their fixed order, those with rows or a read that failed; none unless comparable
            let factorSections: [FactorSection]
            /// under the legend
            let profileNote: String

            func group(_ side: Side) -> Group {
                side == .reference ? reference : compared
            }
        }

        let period: StatsPeriod
        /// "10 Oct – 8 Nov": the period's days, to yesterday
        let dateRange: String
        /// "30 d"
        let periodLabel: String
        let plot: Plot
        /// "Your range 70–145"
        let legendRange: String
        /// why a group's figures are provisional (the limited-data mark)
        let limitedNote: String
        /// under the glucose card: GRI's standard ranges against the Statistics range
        let glucoseNote: String
        let griSheet: GRIInfoSheet.Content
        let content: Content

        /// A stretch's minutes as drawn: one past midnight is two.
        static func drawn(_ minutes: Range<Int>) -> [Range<Int>] {
            let day = StatsClock.minutesPerDay
            guard minutes.upperBound > day else { return [minutes] }
            return [minutes.lowerBound ..< day, 0 ..< minutes.upperBound - day]
        }

        /// "15:00–19:00": a stretch's clock times (its end past midnight as the next day's)
        static func stretch(_ minutes: Range<Int>) -> String {
            let day = StatsClock.minutesPerDay
            return AGP.clockTime(minutes.lowerBound % day) + "–" + AGP.clockTime(minutes.upperBound % day)
        }

        /// "Days are ranked by GRI, …": under the counts
        static var griCaption: String {
            NSLocalizedString(
                "Days are ranked by GRI, the Glycemia Risk Index: 0 is best, 100 worst.",
                comment: "Statistics Good & bad days: what the day score is"
            )
        }

        @MainActor init(_ data: GoodBadDaysData, settings: StatsSettings, now: Date = Date(), calendar: Calendar = .current) {
            typealias Format = StatsFormatting
            let result = data.result
            let bands = settings.bands
            let units = settings.units
            period = data.period
            dateRange = Format.dateRange(result.window, period: data.period, now: now)
            periodLabel = Format.label(data.period)

            let axis = result.axis
            let binCount = AGPSelection.binCount
            let binMinutes = GlucoseStatsEngine.agpBinMinutes
            plot = Plot(
                axis: axis,
                low: bands.low,
                high: bands.high,
                dashed: GlucoseStatsEngine.dashedLevels(bands: bands, axis: axis),
                xTicks: AGP.Plot.gridMinutes.dropLast().map { AGP.Plot.Tick(minute: $0, label: AGP.clockTime($0)) },
                yLabels: GlucoseStatsEngine.labelledLevels(bands: bands, axis: axis)
                    .map { AGP.Plot.Level(mgdl: $0, label: Format.glucose($0, units: units)) },
                binTimes: (0 ..< binCount).map { AGP.clockInterval(from: $0 * binMinutes, to: ($0 + 1) * binMinutes) },
                binStarts: (0 ..< binCount).map { AGP.clockTime($0 * binMinutes) },
                unit: Format.unit(units)
            )
            legendRange = String(
                format: NSLocalizedString("Your range %@", comment: "Statistics AGP legend: the in-range band"),
                Format.label(.inRange, bands: bands, units: units) ?? ""
            )
            limitedNote = ContentBuilder.limitedNote
            glucoseNote = String(
                format: NSLocalizedString(
                    "GRI and the in-range share use the standard ranges (%1$@), not your %2$@, so your settings never move a day between groups.",
                    comment: "Statistics Good & bad days: the standard TIR range, the user's range"
                ),
                Format.range(bands.tirRange, units: units),
                Format.label(.inRange, bands: bands, units: units) ?? ""
            )
            griSheet = GRIInfoSheet.Content(bands: bands, units: units)

            let builder = ContentBuilder(
                result: result,
                factors: data.factors,
                sensorsRecordedFrom: data.sensorsRecordedFrom,
                dayCount: data.period.calendarDayCount ?? 0,
                bands: bands,
                units: units,
                plot: plot,
                now: now,
                calendar: calendar
            )
            content = builder.content()
        }
    }
}

// MARK: - Building

private extension Stat.GoodBadDays {
    /// The content from the result.
    @MainActor struct ContentBuilder {
        typealias Format = StatsFormatting

        let result: GoodBadDaysResult
        let factors: [GoodBadDaysFactorRow]
        /// the first CGM session's start (`GoodBadDaysData.sensorsRecordedFrom`)
        let sensorsRecordedFrom: Date?
        /// the period's days
        let dayCount: Int
        let bands: StatsBands
        let units: GlucoseUnits
        let plot: Plot
        let now: Date
        let calendar: Calendar

        func content() -> Content {
            let split = result.thirds
            let reference = group(split.reference, side: .reference)
            let compared = group(split.compared, side: .compared)
            let comparable = split.isComparable
            // a shown group under 10 days
            let limited = [split.reference, split.compared].contains { $0.isShown && $0.isLimited }
            return Content(
                counts: counts(split),
                lines: lines(split),
                reference: reference,
                compared: compared,
                isComparable: comparable,
                isLimited: limited,
                caption: comparable ? caption(split, compared: compared) : nil,
                message: comparable ? nil : message(reference: reference),
                highlights: split.highlights.flatMap { Stat.GoodBadDays.drawn($0.minutes) },
                openingBin: openingBin(split),
                glucoseRows: comparable ? split.glucoseRows.compactMap { glucoseRow($0) } : [],
                factorIntro: String(
                    format: NSLocalizedString(
                        "Each row: both groups’ median and middle half, then how %1$@ differs from %2$@. A row needs %3$d days with a value in each group.",
                        comment: "Statistics Good & bad days: the factor card's intro (\"the worst third\", \"the best third\", 5)"
                    ),
                    compared.onName,
                    reference.onName,
                    GoodBadDaysEngine.minimumDays
                ),
                factorSections: comparable ? factorSections(factors, reference: reference, compared: compared) : [],
                profileNote: limited ? Self.profileNote + " " + Self.limitedNote : Self.profileNote
            )
        }

        static var profileNote: String {
            NSLocalizedString(
                "The median and the middle half (25–75%) of each group’s days, by time of day.",
                comment: "Statistics Good & bad days: what the chart shows"
            )
        }

        /// why a group's figures are provisional
        static var limitedNote: String {
            String(
                format: NSLocalizedString(
                    "Under %d days in a group: the profile and the figures are provisional.",
                    comment: "Statistics Good & bad days limited data: a group with few days"
                ),
                GoodBadDaysEngine.unlimitedDays
            )
        }

        // MARK: Groups

        /// The groups' names: the name, the column, the "on …" form.
        private func names(_ side: Side) -> (name: String, short: String, on: String) {
            switch side {
            case .reference:
                return (
                    NSLocalizedString("Best third", comment: "Statistics Good & bad days: the days with the lowest GRI"),
                    NSLocalizedString("Best", comment: "Statistics Good & bad days: the best third, a column"),
                    NSLocalizedString("the best third", comment: "Statistics Good & bad days: \"lower on the best third\"")
                )
            case .compared:
                return (
                    NSLocalizedString("Worst third", comment: "Statistics Good & bad days: the days with the highest GRI"),
                    NSLocalizedString("Worst", comment: "Statistics Good & bad days: the worst third, a column"),
                    NSLocalizedString("the worst third", comment: "Statistics Good & bad days: \"lower on the worst third\"")
                )
            }
        }

        private func group(_ group: GoodBadDaysResult.Group, side: Side) -> Group {
            let names = self.names(side)
            let bins = group.isShown ? group.bins : []
            let lower = Double(plot.axis.lowerBound)
            let upper = Double(plot.axis.upperBound)
            return Group(
                side: side,
                name: names.name,
                short: names.short,
                onName: names.on,
                dayCount: group.days.count,
                isShown: group.isShown,
                points: group.isShown ? group.points : [],
                readouts: (0 ..< plot.binCount).map { index -> [String]? in
                    guard index < bins.count, let bin = bins[index] else { return nil }
                    return [bin.p25, bin.p50, bin.p75].map { Format.glucose($0, units: units) }
                },
                plottedMedians: (0 ..< plot.binCount).map { index -> Double? in
                    guard index < bins.count, let bin = bins[index] else { return nil }
                    return Swift.min(Swift.max(bin.p50, lower), upper)
                },
                days: group.days.reversed().map { day($0) },
                title: String(
                    format: NSLocalizedString(
                        "%1$@ (%2$d)",
                        comment: "Statistics Good & bad days: a group and its days (\"Best third (10)\")"
                    ),
                    names.name,
                    group.days.count
                ),
                span: span(group.days)
            )
        }

        /// "1 Oct – 29 Oct": the first and the last day; "None"
        private func span(_ days: [GoodBadDaysResult.ScoredDay]) -> String {
            guard let first = days.first, let last = days.last else {
                return NSLocalizedString("None", comment: "Statistics Good & bad days: a group without days")
            }
            guard last.day.start > first.day.start else {
                return first.day.start.formatted(.dateTime.day().month(.abbreviated))
            }
            return (first.day.start ..< last.day.start).formatted(.interval.day().month(.abbreviated))
        }

        private func day(_ day: GoodBadDaysResult.ScoredDay) -> Day {
            Day(
                id: day.day.start,
                title: Stat.Trace.dayTitle(day.day.start),
                detail: String(
                    format: NSLocalizedString("in range %@", comment: "Statistics Good & bad days: a day's TIR"),
                    Format.percent(fraction: day.tir)
                ),
                segments: day.shares.barSegments(GlucoseBand.allCases),
                gri: Self.gri(day.gri)
            )
        }

        /// "GRI 34 · B": the value, its zone
        static func gri(_ gri: GlycemiaRiskIndex) -> String {
            String(
                format: NSLocalizedString("GRI %1$@ · %2$@", comment: "Statistics Good & bad days: a day's GRI and its zone"),
                "\(Int(gri.value.rounded()))",
                zoneLetter(gri.zone)
            )
        }

        static func zoneLetter(_ zone: GlycemiaRiskIndex.Zone) -> String {
            switch zone {
            case .a: return "A"
            case .b: return "B"
            case .c: return "C"
            case .d: return "D"
            case .e: return "E"
            }
        }

        // MARK: Counts and lines

        private func counts(_ split: GoodBadDaysResult.Split) -> String {
            String(
                format: NSLocalizedString(
                    "%1$d best · %2$d worst · %3$d in between",
                    comment: "Statistics Good & bad days: the thirds' days"
                ),
                split.reference.days.count,
                split.compared.days.count,
                split.leftOut
            )
        }

        private func lines(_ split: GoodBadDaysResult.Split) -> [String] {
            var lines: [String] = []
            if let best = thirdRange(split.reference.days), let worst = thirdRange(split.compared.days) {
                lines.append(String(
                    format: NSLocalizedString(
                        "Best third: GRI %1$@, in range %2$@",
                        comment: "Statistics Good & bad days: the best third's GRI and TIR ranges (\"12–24\", \"81–93%\")"
                    ),
                    best.gri,
                    best.tir
                ))
                lines.append(String(
                    format: NSLocalizedString(
                        "Worst third: GRI %1$@, in range %2$@",
                        comment: "Statistics Good & bad days: the worst third's GRI and TIR ranges (\"38–71\", \"40–62%\")"
                    ),
                    worst.gri,
                    worst.tir
                ))
            }
            if result.unscored > 0 {
                lines.append(
                    result.unscored == 1
                        ? NSLocalizedString(
                            "1 day with too little CGM data left out",
                            comment: "Statistics Good & bad days: a day under 70% CGM coverage"
                        )
                        : String(
                            format: NSLocalizedString(
                                "%d days with too little CGM data left out",
                                comment: "Statistics Good & bad days: days under 70% CGM coverage"
                            ),
                            result.unscored
                        )
                )
            }
            return lines
        }

        /// A third's GRI and TIR ranges: "12–24", "81–93%"; nil without days.
        private func thirdRange(_ days: [GoodBadDaysResult.ScoredDay]) -> (gri: String, tir: String)? {
            let gri = days.map { Int($0.gri.value.rounded()) }
            let tir = days.map { Int(($0.tir * 100).rounded()) }
            guard let griLow = gri.min(), let griHigh = gri.max(), let tirLow = tir.min(), let tirHigh = tir.max() else {
                return nil
            }
            return ("\(griLow)–\(griHigh)", "\(tirLow)–" + Format.percent(tirHigh))
        }

        // MARK: The chart

        private func caption(_ split: GoodBadDaysResult.Split, compared: Group) -> String {
            guard let main = split.highlights.first else {
                return String(
                    format: NSLocalizedString(
                        "The medians are within %1$@ %2$@ of each other all day.",
                        comment: "Statistics Good & bad days: no stretch where the medians differ much (\"20\", \"mg/dL\")"
                    ),
                    Format.glucose(Int(GoodBadDaysEngine.highlightFloor), units: units),
                    plot.unit
                )
            }
            let stretch = Stat.GoodBadDays.stretch(main.minutes)
            let reference = Format.glucose(main.reference, units: units)
            let comparedValue = Format.glucose(main.compared, units: units)
            guard main.isHigher else {
                return String(
                    format: NSLocalizedString(
                        "Medians differ most %1$@: %2$@ vs %3$@ %4$@, lower on %5$@",
                        comment: "Statistics Good & bad days: the main stretch, both medians, the unit, the lower group"
                    ),
                    stretch,
                    reference,
                    comparedValue,
                    plot.unit,
                    compared.onName
                )
            }
            return String(
                format: NSLocalizedString(
                    "Medians differ most %1$@: %2$@ vs %3$@ %4$@",
                    comment: "Statistics Good & bad days: the main stretch, both medians, the unit"
                ),
                stretch,
                reference,
                comparedValue,
                plot.unit
            )
        }

        /// The main stretch's middle hour; the clock time now without a stretch (as the AGP opens).
        private func openingBin(_ split: GoodBadDaysResult.Split) -> Int {
            let binCount = plot.binCount
            guard let main = split.highlights.first else {
                return GlucoseStatsEngine.agpBin(of: now, calendar: calendar, binCount: binCount)
            }
            let middle = (main.minutes.lowerBound + main.minutes.upperBound) / 2
            let hour = (middle / 60 * 60) % StatsClock.minutesPerDay
            return GlucoseStatsEngine.agpBin(atMinute: hour, binCount: binCount)
        }

        /// The thirds under `GoodBadDaysEngine.minimumDays` days each (under 14 days scored).
        private func message(reference: Group) -> Message {
            Message(
                title: String(
                    format: NSLocalizedString(
                        "Too few days: each group needs at least %d",
                        comment: "Statistics Good & bad days: a group under the minimum"
                    ),
                    GoodBadDaysEngine.minimumDays
                ),
                detail: String(
                    format: NSLocalizedString(
                        "%1$d of %2$d days scored, so each third has %3$d.",
                        comment: "Statistics Good & bad days: the thirds of too few days"
                    ),
                    result.scored,
                    dayCount,
                    reference.dayCount
                )
            )
        }

        // MARK: Glucose rows

        private func glucoseRow(_ row: GoodBadDaysResult.GlucoseRow) -> GlucoseRow? {
            guard let reference = row.reference, let compared = row.compared else { return nil }
            let name: String
            let detail: String?
            let format: (Double) -> String
            let difference: String
            switch row.id {
            case .gri:
                name = NSLocalizedString("GRI", comment: "Statistics Good & bad days: the Glycemia Risk Index")
                detail = nil
                format = { "\(Int($0.rounded()))" }
                difference = Self.signed(Int(compared.median.rounded()) - Int(reference.median.rounded()))
            case .tir:
                name = NSLocalizedString("In range", comment: "Statistics Good & bad days: TIR")
                detail = Format.range(bands.tirRange, units: units)
                format = { "\(Int(($0 * 100).rounded()))" }
                difference = Self.points(
                    Double(Int((compared.median * 100).rounded()) - Int((reference.median * 100).rounded())),
                    digits: 0
                )
            case .below70:
                name = String(
                    format: NSLocalizedString("Below %@", comment: "Statistics Good & bad days: the time below 70"),
                    Format.glucose(bands.tirRange.lowerBound, units: units)
                )
                detail = nil
                format = { Self.oneDecimal($0 * 100) }
                difference = Self.points(((compared.median - reference.median) * 1000).rounded() / 10, digits: 1)
            case .mean:
                name = NSLocalizedString("Mean", comment: "Statistics Good & bad days: the mean glucose")
                detail = plot.unit
                format = { Format.glucose($0, units: units) }
                // the difference as shown: ±0 when it rounds to nothing
                let delta = compared.median - reference.median
                let shown = Format.glucose(abs(delta), units: units)
                difference = Self.sign(of: shown == Format.glucose(0.0, units: units) ? 0 : delta) + shown
            case .nightTIR:
                name = NSLocalizedString("In range at night", comment: "Statistics Good & bad days: TIR of 00:00–06:00")
                detail = Stat.AGP.clockInterval(from: 0, to: GoodBadDaysEngine.nightEndMinute)
                format = { "\(Int(($0 * 100).rounded()))" }
                difference = Self.points(
                    Double(Int((compared.median * 100).rounded()) - Int((reference.median * 100).rounded())),
                    digits: 0
                )
            }
            let isPercent = row.id == .tir || row.id == .below70 || row.id == .nightTIR
            func cell(_ values: GoodBadDaysResult.Values) -> GlucoseRow.Cell {
                GlucoseRow.Cell(
                    value: isPercent ? format(values.median) + "%" : format(values.median),
                    range: "(" + format(values.p25) + "–" + format(values.p75) + ")"
                )
            }
            return GlucoseRow(
                id: row.id,
                name: name,
                detail: detail,
                reference: cell(reference),
                compared: cell(compared),
                difference: difference
            )
        }

        // MARK: Factors

        private func factorSections(_ rows: [GoodBadDaysFactorRow], reference: Group, compared: Group) -> [FactorSection] {
            GoodBadFactor.Section.allCases.compactMap { section -> FactorSection? in
                let sectionRows = rows.filter { $0.id.section == section }
                let shown = sectionRows.filter(\.isShown).map { factorRow($0, reference: reference, compared: compared) }
                let unavailable = sectionRows.first(where: \.unavailable).flatMap { unavailableNote($0.id.source) }
                guard shown.isNotEmpty || unavailable != nil else { return nil }
                return FactorSection(
                    id: section,
                    title: title(section),
                    note: note(section),
                    unavailable: unavailable,
                    rows: shown
                )
            }
        }

        private func title(_ section: GoodBadFactor.Section) -> String {
            switch section {
            case .meals: return NSLocalizedString("Meals", comment: "Statistics topic")
            case .insulin: return NSLocalizedString("Insulin", comment: "Statistics topic")
            case .loopResponse: return NSLocalizedString(
                    "What you and the loop did",
                    comment: "Statistics Good & bad days: the SMB, zero basal and basal rows"
                )
            case .site: return NSLocalizedString("Site", comment: "Statistics Good & bad days: the pump site's rows")
            case .cgmSensor: return NSLocalizedString("CGM sensor", comment: "Statistics Good & bad days: the sensor's rows")
            case .loopAndCGM: return NSLocalizedString("Loop and CGM", comment: "Statistics Good & bad days: a section")
            case .calendar: return NSLocalizedString("Calendar", comment: "Statistics Good & bad days: a section")
            }
        }

        private func note(_ section: GoodBadFactor.Section) -> String? {
            switch section {
            case .meals:
                return String(
                    format: NSLocalizedString(
                        "Low treatments are left out: carb entries made during a low (below %1$@), or within %2$d min after it ends.",
                        comment: "Statistics Good & bad days: the meal rows (\"70 mg/dL\", 30)"
                    ),
                    Format.glucose(GoodBadDaysEngine.lowTreatmentBelow, units: units) + " " + plot.unit,
                    Int(GoodBadDaysEngine.lowTreatmentAfter / 60)
                )
            case .insulin:
                return NSLocalizedString(
                    "Days with pump data for at least half of the day.",
                    comment: "Statistics Good & bad days: the insulin rows' days"
                )
            case .loopResponse:
                return NSLocalizedString(
                    "These follow glucose: a bad day brings more corrections and more time at zero basal.",
                    comment: "Statistics Good & bad days: the loop rows are a result, not a cause"
                )
            case .calendar,
                 .cgmSensor,
                 .loopAndCGM,
                 .site: return nil
            }
        }

        /// A failed read, by what it read; nil for the glucose, whose rows come with the result, and the CGM sessions,
        /// whose read gives none when it fails.
        private func unavailableNote(_ source: GoodBadFactor.Source) -> String? {
            switch source {
            case .meals: return NSLocalizedString("The carb entries couldn't be read.", comment: "Statistics: a failed read")
            case .insulin: return NSLocalizedString("The pump data couldn't be read.", comment: "Statistics: a failed read")
            case .sessions: return NSLocalizedString("The pump sessions couldn't be read.", comment: "Statistics: a failed read")
            case .loops: return NSLocalizedString("The loop records couldn't be read.", comment: "Statistics: a failed read")
            case .cgmSessions,
                 .glucose: return nil
            }
        }

        private func name(_ factor: GoodBadFactor) -> String {
            switch factor {
            case .carbs: return NSLocalizedString("Carbs", comment: "Statistics Good & bad days: a day's carbs")
            case .largestMeal: return NSLocalizedString("Largest meal", comment: "Statistics Good & bad days: a factor")
            case .meals: return NSLocalizedString("Meals", comment: "Statistics Good & bad days: the meals of 5 g or more")
            case .lastMeal: return NSLocalizedString("Last meal", comment: "Statistics Good & bad days: its start")
            case .lateCarbs: return NSLocalizedString("Late carbs", comment: "Statistics Good & bad days: carbs from 21:00")
            case .fatAndProtein: return NSLocalizedString("Fat + protein", comment: "Statistics Good & bad days: a factor")
            case .lateCarbsEveningBefore: return NSLocalizedString(
                    "Late carbs the evening before",
                    comment: "Statistics Good & bad days: the day before's late carbs"
                )
            case .totalInsulin: return NSLocalizedString("Total insulin", comment: "Statistics Good & bad days: a factor")
            case .bolusShare: return NSLocalizedString("Bolus share", comment: "Statistics Good & bad days: a factor")
            case .lateBolus: return NSLocalizedString(
                    "Meals with a late or no bolus",
                    comment: "Statistics Good & bad days: a factor"
                )
            case .smb: return NSLocalizedString("SMB", comment: "Statistics Good & bad days: a factor")
            case .zeroBasal: return NSLocalizedString("Time at zero basal", comment: "Statistics Good & bad days: a factor")
            case .basalVsScheduled: return NSLocalizedString(
                    "Basal vs scheduled",
                    comment: "Statistics Good & bad days: a factor"
                )
            case .siteDay: return NSLocalizedString("Site day", comment: "Statistics Good & bad days: the wear day")
            case .siteChange: return NSLocalizedString("Site change that day", comment: "Statistics Good & bad days: a factor")
            case .sensorDay: return NSLocalizedString("Sensor day", comment: "Statistics Good & bad days: the CGM sensor's day")
            case .sensorChange: return NSLocalizedString(
                    "Sensor change that day",
                    comment: "Statistics Good & bad days: a factor"
                )
            case .loopSuccess: return NSLocalizedString("Loop success", comment: "Statistics Good & bad days: a factor")
            case .cgmCoverage: return NSLocalizedString("CGM coverage", comment: "Statistics Good & bad days: a factor")
            case .weekend: return NSLocalizedString("Weekend days", comment: "Statistics Good & bad days: a factor")
            case .previousGRI: return NSLocalizedString("Previous day’s GRI", comment: "Statistics Good & bad days: a factor")
            }
        }

        private func note(_ factor: GoodBadFactor) -> String? {
            switch factor {
            case .lateCarbs:
                return String(
                    format: NSLocalizedString("Entries from %@ to midnight.", comment: "Statistics Good & bad days: late carbs"),
                    Stat.AGP.clockTime(GoodBadDaysEngine.lateCarbsFromMinute)
                )
            case .lateBolus:
                return String(
                    format: NSLocalizedString(
                        "Meals of %1$@ or more with no bolus by %2$d min after the start. Moderately reliable: a meal entered at bolus time hides a late bolus.",
                        comment: "Statistics Good & bad days: the late or no bolus row (\"10 g\", 15)"
                    ),
                    Self.grams(GoodBadDaysEngine.bolusMealMinimumCarbs),
                    Int(GoodBadDaysEngine.bolusLateAfter / 60)
                )
            case .siteDay:
                return NSLocalizedString(
                    "The wear day at noon, counted from the change.",
                    comment: "Statistics Good & bad days: the site day"
                )
            case .sensorDay:
                // without a session the rows have no values
                guard let sensorsRecordedFrom else { return nil }
                return String(
                    format: NSLocalizedString(
                        "At noon; sensors started before %@ weren’t recorded.",
                        comment: "Statistics Good & bad days: the sensor day, the first CGM session's start (\"4 Oct\")"
                    ),
                    CGMFormat.day(sensorsRecordedFrom)
                )
            default:
                return nil
            }
        }

        private func factorRow(_ row: GoodBadDaysFactorRow, reference: Group, compared: Group) -> FactorRow {
            let kind = row.id.kind
            let values: String
            let difference: (value: String, sign: Int)
            if kind == .yesNo, let referenceValues = row.reference, let comparedValues = row.compared {
                values = String(
                    format: NSLocalizedString(
                        "%1$@ %2$d of %3$d days · %4$@ %5$d of %6$d days",
                        comment: "Statistics Good & bad days: a yes/no row (\"Best 4 of 10 days · Worst 5 of 5 days\")"
                    ),
                    reference.short,
                    row.referenceYes,
                    referenceValues.n,
                    compared.short,
                    row.comparedYes,
                    comparedValues.n
                )
                let points = Int((Double(row.comparedYes) / Double(Swift.max(comparedValues.n, 1)) * 100).rounded())
                    - Int((Double(row.referenceYes) / Double(Swift.max(referenceValues.n, 1)) * 100).rounded())
                difference = (Self.pointsMagnitude(Double(abs(points)), digits: 0), points.signum())
            } else if let referenceValues = row.reference, let comparedValues = row.compared {
                var line = String(
                    format: NSLocalizedString(
                        "%1$@ %2$@ (%3$@) · %4$@ %5$@ (%6$@) · n %7$d / %8$d",
                        comment: "Statistics Good & bad days: a factor row, both groups' median (IQR), their days"
                    ),
                    reference.short,
                    factorValue(kind, referenceValues.median),
                    factorRange(kind, referenceValues),
                    compared.short,
                    factorValue(kind, comparedValues.median),
                    factorRange(kind, comparedValues),
                    referenceValues.n,
                    comparedValues.n
                )
                if row.notLogged > 0 {
                    line += " · " + Self.notLogged(row.notLogged, dayBefore: row.id == .lateCarbsEveningBefore)
                }
                values = line
                difference = factorDifference(kind, from: referenceValues.median, to: comparedValues.median)
            } else {
                values = ""
                difference = ("", 0)
            }
            let later = kind == .minuteOfDay
            let direction: String
            if difference.sign > 0 {
                direction = later
                    ? NSLocalizedString("later", comment: "Statistics Good & bad days: a difference's direction")
                    : NSLocalizedString("more", comment: "Statistics Good & bad days: a difference's direction")
            } else if difference.sign < 0 {
                direction = later
                    ? NSLocalizedString("earlier", comment: "Statistics Good & bad days: a difference's direction")
                    : NSLocalizedString("less", comment: "Statistics Good & bad days: a difference's direction")
            } else {
                direction = NSLocalizedString("the same", comment: "Statistics Good & bad days: no difference")
            }
            return FactorRow(
                id: row.id,
                name: name(row.id),
                values: values,
                difference: Self.sign(of: Double(difference.sign)) + difference.value,
                direction: direction,
                note: note(row.id)
            )
        }

        /// A value as the row shows it: "142 g", "1.2 U", "62%", "3", "19:30", "2", "34".
        private func factorValue(_ kind: GoodBadFactor.Kind, _ value: Double) -> String {
            switch kind {
            case .grams: return Self.grams(value.rounded())
            case .units: return Self.units(value)
            case .fraction,
                 .yesNo: return Format.percent(fraction: value)
            case .count,
                 .wearDay: return Self.upToOneDecimal(value)
            case .minuteOfDay: return Stat.AGP.clockTime(Int(value.rounded()) % StatsClock.minutesPerDay)
            case .gri: return "\(Int(value.rounded()))"
            }
        }

        /// The IQR as the row shows it: "120–160", "1.0–1.5", "50–70", "18:30–19:45".
        private func factorRange(_ kind: GoodBadFactor.Kind, _ values: GoodBadDaysResult.Values) -> String {
            switch kind {
            case .grams,
                 .gri: return "\(Int(values.p25.rounded()))–\(Int(values.p75.rounded()))"
            case .units: return Self.oneDecimal(values.p25) + "–" + Self.oneDecimal(values.p75)
            case .fraction,
                 .yesNo: return "\(Int((values.p25 * 100).rounded()))–\(Int((values.p75 * 100).rounded()))"
            case .count,
                 .wearDay: return Self.upToOneDecimal(values.p25) + "–" + Self.upToOneDecimal(values.p75)
            case .minuteOfDay:
                return Stat.AGP.clockTime(Int(values.p25.rounded()) % StatsClock.minutesPerDay) + "–"
                    + Stat.AGP.clockTime(Int(values.p75.rounded()) % StatsClock.minutesPerDay)
            }
        }

        /// compared − reference, of the values as shown: its size ("46 g", "0.4 U", "12 pt", "1 h 05 m") and its sign.
        private func factorDifference(_ kind: GoodBadFactor.Kind, from reference: Double, to compared: Double)
            -> (value: String, sign: Int)
        {
            switch kind {
            case .grams:
                let delta = Int(compared.rounded()) - Int(reference.rounded())
                return (Self.grams(Double(abs(delta))), delta.signum())
            case .units:
                let delta = ((compared - reference) * 10).rounded() / 10
                return (Self.units(abs(delta)), delta > 0 ? 1 : delta < 0 ? -1 : 0)
            case .fraction,
                 .yesNo:
                let delta = Int((compared * 100).rounded()) - Int((reference * 100).rounded())
                return (Self.pointsMagnitude(Double(abs(delta)), digits: 0), delta.signum())
            case .count,
                 .wearDay:
                let delta = ((compared - reference) * 10).rounded() / 10
                return (Self.upToOneDecimal(abs(delta)), delta > 0 ? 1 : delta < 0 ? -1 : 0)
            case .minuteOfDay:
                // to 5 minutes: a clock time to the minute says more than the data does
                let delta = Int(((compared - reference) / 5).rounded()) * 5
                return (Format.duration(minutes: Double(abs(delta))), delta.signum())
            case .gri:
                let delta = Int(compared.rounded()) - Int(reference.rounded())
                return ("\(abs(delta))", delta.signum())
            }
        }

        /// "no meals logged on 2 days": the group days without a meal entry (low treatments apart); the evening before's
        /// row counts the days whose day before had none
        static func notLogged(_ days: Int, dayBefore: Bool) -> String {
            switch (dayBefore, days == 1) {
            case (false, true):
                return NSLocalizedString(
                    "no meals logged on 1 day",
                    comment: "Statistics Good & bad days: a day without meal entries"
                )
            case (false, false):
                return String(
                    format: NSLocalizedString(
                        "no meals logged on %d days",
                        comment: "Statistics Good & bad days: the days without meal entries"
                    ),
                    days
                )
            case (true, true):
                return NSLocalizedString(
                    "no meals logged the day before on 1 day",
                    comment: "Statistics Good & bad days: a day whose day before has no meal entries"
                )
            case (true, false):
                return String(
                    format: NSLocalizedString(
                        "no meals logged the day before on %d days",
                        comment: "Statistics Good & bad days: the days whose day before has no meal entries"
                    ),
                    days
                )
            }
        }

        /// "142 g"
        static func grams(_ value: Double) -> String {
            String(format: NSLocalizedString("%@ g", comment: "Statistics: grams"), "\(Int(value.rounded()))")
        }

        /// "1.2 U"
        static func units(_ value: Double) -> String {
            String(format: NSLocalizedString("%@ U", comment: "Statistics: insulin units"), oneDecimal(value))
        }

        /// "3", "2.5": no needless decimal (a median of an even count can be a half)
        static func upToOneDecimal(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0 ... 1)))
        }

        // MARK: Numbers

        /// "+", "−" or "±" before a difference of its sign
        static func sign(of value: Double) -> String {
            value > 0 ? "+" : value < 0 ? "−" : "±"
        }

        /// "+12", "−3", "±0"
        static func signed(_ value: Int) -> String {
            sign(of: Double(value)) + "\(abs(value))"
        }

        /// "1.2", the locale's decimal separator
        static func oneDecimal(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(1)))
        }

        /// "+4 pt", "−0.8 pt": a difference of percentages
        static func points(_ value: Double, digits: Int) -> String {
            sign(of: value) + pointsMagnitude(value, digits: digits)
        }

        /// "4 pt", "0.8 pt": a difference of percentages without its sign
        static func pointsMagnitude(_ value: Double, digits: Int) -> String {
            String(
                format: NSLocalizedString("%@ pt", comment: "Statistics Good & bad days: a difference in percentage points"),
                abs(value).formatted(.number.precision(.fractionLength(digits)))
            )
        }
    }
}
