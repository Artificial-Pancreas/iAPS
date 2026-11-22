import SwiftUI

// The Patches, CGM and Settings parts' print views. The Patches list's heights are `ReportPatchesLayout`'s and the
// Settings schedules' `ReportSettingsLayout`'s, which the plan counts pages with.

/// A line of a list: a name, a longer text after it, a number at the trailing edge.
private struct ReportListRow: View {
    let name: String
    let detail: String
    let value: String
    let width: CGFloat
    var nameWidth: CGFloat = 130
    var valueWidth: CGFloat = 60
    var height: CGFloat = ReportPatchesLayout.rowHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                reportCell(name)
                    .frame(width: nameWidth - 6, alignment: .leading)
                    .padding(.trailing, 6)
                reportCell(detail, size: 8, secondary: true)
                    .frame(width: width - nameWidth - valueWidth, alignment: .leading)
                reportCell(value, weight: .semibold)
                    .frame(width: valueWidth, alignment: .trailing)
            }
            .frame(width: width, height: height - 0.5, alignment: .leading)
            reportRule(width)
        }
    }
}

// MARK: - Patches

struct ReportPatchesContent: View {
    typealias Layout = ReportPatchesLayout
    typealias Tables = ReportTablesLayout

    let page: Stat.ReportPatches
    /// the content's, points
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else {
                if page.isFirst {
                    summary
                    wearDays
                }
                list
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The count and the tiles, then the note about the period: in `Layout.summaryHeight` and `Layout.noteHeight`.
    @ViewBuilder private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                reportCell(page.count, size: 18, weight: .bold)
                    .fixedSize()
                reportCell(page.countDetail, size: 8.5, secondary: true)
            }
            ReportFiguresRow(figures: page.figures, width: width)
        }
        .frame(width: width, height: Layout.summaryHeight, alignment: .topLeading)
        note(page.periodNote ?? "", lines: 3, height: Layout.periodNoteHeight)
    }

    private func note(_ text: String, lines: Int = 2, height: CGFloat = Layout.noteHeight) -> some View {
        Text(text)
            .font(ReportStyle.font(7))
            .foregroundStyle(ReportStyle.secondary)
            .lineLimit(lines)
            .minimumScaleFactor(0.7)
            .padding(.top, 3)
            .frame(width: width, height: height, alignment: .topLeading)
    }

    @ViewBuilder private var wearDays: some View {
        ReportTableTitle(text: NSLocalizedString("By wear day", comment: ""), width: width)
        ReportTableView(table: page.wearDays, width: width, nameWidth: 110)
        note(page.wearDayNote + (page.wearDaysCut.map { " " + $0 } ?? ""))
    }

    @ViewBuilder private var list: some View {
        ReportTableTitle(text: page.listTitle, width: width)
        HStack(spacing: 0) {
            reportCell(
                NSLocalizedString("Worn", comment: "PDF report, Patches: the days a patch was worn"),
                size: 7.5,
                weight: .semibold
            )
            .frame(width: 130, alignment: .leading)
            Spacer(minLength: 0)
            reportCell(StatsFormatting.name(.inRange), size: 7.5, weight: .semibold)
                .fixedSize()
        }
        .frame(width: width, height: Tables.headerHeight - 0.5, alignment: .bottomLeading)
        reportRule(width, strong: true)
        ForEach(page.rows) { row in
            ReportListRow(name: row.span, detail: row.detail, value: row.inRange, width: width)
        }
    }
}

// MARK: - CGM

struct ReportCGMContent: View {
    let page: Stat.ReportCGM
    /// the content's, points
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else if let report = page.report {
                if page.kind == .overview {
                    overview(report)
                } else {
                    sensors(report)
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    @ViewBuilder private func overview(_ report: Stat.CGMReport) -> some View {
        let readings = report.overview.readings
        if let omitted = page.omittedNote {
            reportNote(omitted, width: width)
        }
        ReportSection(title: readings.title) {
            if let unknown = page.unknownNote {
                longNote(unknown)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                reportCell(readings.coverage, size: 18, weight: .bold)
                    .fixedSize()
                reportCell(readings.coverageDetail, size: 8.5, secondary: true)
            }
            ReportFiguresRow(
                figures: readings.tiles.map { Stat.ReportFigure(id: $0.id, title: $0.title, value: $0.value, unit: $0.unit) },
                width: width
            )
            // the note says so itself when the readings are few (`limitedNote`)
            longNote(readings.note)
        }
        if let rate = report.overview.rate {
            ReportSection(title: NSLocalizedString("Rate of change", comment: "") + " · " + rate.unitTitle) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rate.rows) { row in
                        ReportListRow(
                            name: row.name,
                            detail: row.range + " · " + row.perDay,
                            value: row.percent,
                            width: Swift.min(width, 360),
                            nameWidth: 90,
                            height: 13
                        )
                    }
                }
                if let fastest = rate.fastest {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        reportCell(fastest.title, size: 8.5, weight: .semibold)
                            .fixedSize()
                        reportCell(fastest.value, size: 8.5)
                            .fixedSize()
                        reportCell(fastest.detail, size: 7.5, secondary: true)
                    }
                }
                longNote(rate.note)
            }
        }
        if let comparison = report.overview.comparison {
            ReportSection(title: NSLocalizedString("By CGM", comment: "")) {
                ReportTableView(
                    table: Stat.ReportTable(
                        name: "",
                        columns: comparison.columns.enumerated().map { index, name in
                            Stat.ReportTable.Column(id: index, title: name, subtitle: "")
                        },
                        rows: comparison.rows.map { row in
                            Stat.ReportTable.Row(
                                id: row.id,
                                title: row.unit.isEmpty ? row.name : row.name + ", " + row.unit,
                                cells: row.values
                            )
                        }
                    ),
                    width: width,
                    nameWidth: 170
                )
                longNote(comparison.note)
            }
        }
    }

    /// A card's definitions: a few lines of small text.
    private func longNote(_ text: String) -> some View {
        Text(text)
            .font(ReportStyle.font(7))
            .foregroundStyle(ReportStyle.secondary)
            .lineLimit(6)
            .minimumScaleFactor(0.8)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func sensors(_ report: Stat.CGMReport) -> some View {
        ReportSection(title: NSLocalizedString("Sensor by sensor", comment: "Statistics CGM Sensors: the list of the sensors")) {
            if page.sensors.isEmpty {
                reportNote(report.sensors.emptyText, width: width)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        reportCell(
                            NSLocalizedString("Sensor", comment: "PDF report, CGM: the sensors' column"),
                            size: 7.5,
                            weight: .semibold
                        )
                        .frame(width: 130, alignment: .leading)
                        Spacer(minLength: 0)
                        reportCell(
                            NSLocalizedString(
                                "of its expected life",
                                comment: "PDF report, CGM: a sensor's length as a share of its life"
                            ),
                            size: 7.5,
                            weight: .semibold
                        )
                        .fixedSize()
                    }
                    .frame(width: width, height: 14, alignment: .bottomLeading)
                    reportRule(width, strong: true)
                    ForEach(page.sensors) { sensor in
                        ReportListRow(
                            name: sensor.title,
                            detail: sensor.span + (sensor.noise == "–" ? "" : " · " + sensor.noise),
                            value: sensor.life,
                            width: width,
                            nameWidth: 190,
                            height: Stat.ReportCGM.sensorRowHeight
                        )
                    }
                }
                if let more = page.moreSensors {
                    reportNote(more, width: width)
                }
            }
        }
        if let bars = page.noiseBars {
            ReportSection(title: NSLocalizedString("Noise by sensor day", comment: "")) {
                ReportBarsChart(bars: bars, size: CGSize(width: Swift.min(width, 420), height: 110))
                ReportBarsLegend(items: bars.legend)
                if let callout = report.sensors.noiseCallout {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        reportCell(callout.title, size: 8.5, weight: .semibold)
                            .fixedSize()
                        reportCell(callout.value, size: 8.5)
                            .fixedSize()
                        reportCell(callout.detail, size: 7.5, secondary: true)
                    }
                }
                reportNote(page.noiseNote, width: width)
            }
        }
    }
}

// MARK: - Settings

struct ReportSettingsContent: View {
    typealias Layout = ReportSettingsLayout

    let page: Stat.ReportSettingsPage
    /// the content's, points
    let width: CGFloat

    private static let gap: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let emptyNote = page.emptyNote {
                reportEmpty(emptyNote)
            } else {
                Text(page.intro + " " + page.unitsNote)
                    .font(ReportStyle.font(8))
                    .foregroundStyle(ReportStyle.text)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(width: width, height: Layout.introHeight, alignment: .topLeading)
                if page.schedules.isNotEmpty {
                    schedules
                }
                if page.groups.isNotEmpty {
                    groups
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    /// The schedules side by side, each a column of its steps.
    @ViewBuilder private var schedules: some View {
        let count = CGFloat(Swift.max(page.schedules.count, 1))
        let column = (width - Self.gap * (count - 1)) / count
        ReportTableTitle(text: NSLocalizedString("Schedules", comment: "PDF report, Settings: the daily schedules"), width: width)
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(page.schedules) { schedule in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        reportCell(schedule.title, size: 8, weight: .semibold)
                        Spacer(minLength: 0)
                        reportCell(schedule.unit, size: 6.5, secondary: true)
                            .fixedSize()
                    }
                    .frame(width: column, height: Layout.headerHeight - 0.5, alignment: .bottomLeading)
                    reportRule(column, strong: true)
                    ForEach(schedule.rows) { row in
                        HStack(spacing: 0) {
                            reportCell(row.time, size: 8)
                                .frame(width: column * 0.5, alignment: .leading)
                            reportCell(row.value, size: 8, weight: .semibold)
                                .frame(width: column * 0.5, alignment: .trailing)
                        }
                        .frame(width: column, height: page.rowHeight - 0.5, alignment: .leading)
                        reportRule(column)
                    }
                    if schedule.rows.isEmpty {
                        reportCell("–", size: 8, secondary: true)
                            .frame(width: column, height: page.rowHeight, alignment: .leading)
                    }
                    if let total = schedule.total {
                        reportCell(total, size: 8, weight: .semibold)
                            .frame(width: column, height: page.rowHeight, alignment: .leading)
                    }
                }
                .frame(width: column, alignment: .topLeading)
            }
        }
        .padding(.bottom, 8)
    }

    /// The other values in groups side by side: a name and its value a line.
    @ViewBuilder private var groups: some View {
        let count = CGFloat(Swift.max(page.groups.count, 1))
        let column = (width - Self.gap * (count - 1)) / count
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(page.groups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    ReportTableTitle(text: group.title, width: column)
                    ForEach(group.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            reportCell(row.title, size: 8)
                            Spacer(minLength: 2)
                            reportCell(row.value, size: 8, weight: .semibold)
                                .fixedSize()
                            if let unit = row.unit {
                                reportCell(unit, size: 6.5, secondary: true)
                                    .fixedSize()
                            }
                        }
                        .frame(width: column, height: 12.5, alignment: .leading)
                        reportRule(column)
                    }
                }
                .frame(width: column, alignment: .topLeading)
            }
        }
    }
}
