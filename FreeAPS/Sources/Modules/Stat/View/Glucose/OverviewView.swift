import SwiftUI

extension Stat {
    /// The Overview, formatted for display. The numbers come ready from the service (`GlucoseSummary`).
    struct Overview: Equatable {
        let dateRange: String
        /// why the numbers are provisional (CGM coverage below 70%, `StatsFormatting.coverageNote`): marked on the
        /// headline and the coverage tile; nil when the data isn't limited
        let coverageNote: String?
        let inRangePercent: String
        /// "70–145 mg/dL"
        let inRangeRange: String
        let segments: [BandSegment]
        /// with the time per day
        let rows: [StatsBandRow]
        let tirTitle: String
        let tir: String
        let titrTitle: String
        let titr: String
        let unit: String
        let mean: String
        let sd: String
        let cv: String
        let a1cUnit: String
        let gmi: String
        let eA1c: String
        /// why the A1c estimates are provisional (fewer than 14 days with readings, `StatsFormatting.a1cNote`): marked
        /// on both
        let a1cNote: String?
        let coverage: String
        let daysWithData: String

        var isLimited: Bool { coverageNote != nil }

        @MainActor init(_ summary: GlucoseSummary, period: StatsPeriod, settings: StatsSettings) {
            typealias Format = StatsFormatting
            let bands = summary.bands
            let units = settings.units
            let visible = bands.visibleBands

            dateRange = Format.dateRange(summary.window, period: period)
            coverageNote = Format.coverageNote(summary)
            inRangePercent = Format.percentNumber(.inRange, of: summary)
            inRangeRange = Format.inRangeLabel(bands: bands, units: units)
            segments = summary.bandShares.barSegments(visible)
            rows = visible.map { band in
                StatsBandRow(
                    band: band,
                    name: Format.name(band),
                    range: Format.label(band, bands: bands, units: units) ?? "",
                    perDay: Format.perDay(summary.fraction(band)),
                    percent: Format.percent(band, of: summary)
                )
            }

            tirTitle = Format.tirTitle(bands: bands, units: units)
            tir = Format.percent(summary.tirPercent)
            titrTitle = Format.titrTitle(bands: bands, units: units)
            titr = Format.percent(summary.titrPercent)

            unit = Format.unit(units)
            mean = summary.mean.map { Format.glucose($0, units: units) } ?? "–"
            sd = summary.sd.map { Format.glucose($0, units: units) } ?? "–"
            cv = summary.cv.map { Format.percent(Int($0.rounded())) } ?? "–"

            a1cUnit = Format.a1cUnit(settings.hbA1cUnit)
            gmi = Format.a1c(summary.gmiPercent, unit: settings.hbA1cUnit)
            eA1c = Format.a1c(summary.eA1cPercent, unit: settings.hbA1cUnit)
            a1cNote = Format.a1cNote(summary)

            coverage = Format.percent(summary.coveragePercent)
            daysWithData = Format.days(summary.daysWithData, of: summary.calendarDays)
        }
    }
}

struct OverviewView: View {
    let overview: Stat.Overview

    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 54

    var body: some View {
        VStack(spacing: 16) {
            StatsCard { timeInRanges }
            StatsCard { standardRanges }
            StatsCard { glucose }
        }
    }

    // MARK: - Time in ranges

    @ViewBuilder private var timeInRanges: some View {
        StatsCardHeader(title: "Time in ranges", range: overview.dateRange)

        HStack(alignment: .bottom, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(overview.inRangePercent)
                    .font(.system(size: headlineSize, weight: .bold))
                    .monospacedDigit()
                Text(verbatim: "%")
                    .font(.title.weight(.semibold))
                if let coverageNote = overview.coverageNote {
                    LimitedDataMarker(note: coverageNote, font: .title3)
                        .padding(.leading, 4)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    BandSwatch(band: .inRange, size: 10)
                    Text("in your range")
                        .font(.subheadline.weight(.semibold))
                }
                Text(overview.inRangeRange)
                    .statsFootnote()
            }
            .padding(.bottom, 5)
        }

        BandBar(segments: overview.segments)
            .frame(height: 28)

        bandRows
    }

    private var bandRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("Per day")
                Text(verbatim: "%")
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .statsColumnHeader()

            StatsDividedRows(overview.rows) { row in
                StatsBandRowView(row: row)
            }
        }
    }

    // MARK: - Standard ranges

    @ViewBuilder private var standardRanges: some View {
        Text("Standard ranges")
            .statsSectionTitle()
        HStack(spacing: 12) {
            StatTile(title: overview.tirTitle, value: overview.tir)
            StatTile(title: overview.titrTitle, value: overview.titr)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Glucose

    @ViewBuilder private var glucose: some View {
        Text("Glucose")
            .statsSectionTitle()
        VStack(spacing: 12) {
            StatTile(
                title: NSLocalizedString("Mean", comment: "Statistics, mean glucose"),
                value: overview.mean,
                unit: overview.unit
            )
            HStack(spacing: 12) {
                StatTile(title: NSLocalizedString("SD", comment: ""), value: overview.sd, unit: overview.unit)
                StatTile(title: NSLocalizedString("CV", comment: ""), value: overview.cv)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                a1cTile(NSLocalizedString("GMI", comment: "Glucose management indicator"), value: overview.gmi)
                a1cTile(NSLocalizedString("eA1c", comment: "Estimated A1c (ADAG)"), value: overview.eA1c)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                StatTile(
                    title: NSLocalizedString("CGM coverage", comment: "Statistics"),
                    value: overview.coverage,
                    limitedNote: overview.coverageNote,
                    style: .secondary
                )
                StatTile(
                    title: NSLocalizedString("Days with data", comment: "Statistics"),
                    value: overview.daysWithData,
                    style: .secondary
                )
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func a1cTile(_ title: String, value: String) -> some View {
        StatTile(
            title: title,
            value: value,
            unit: overview.a1cUnit,
            limitedNote: overview.a1cNote
        )
    }
}
