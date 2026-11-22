import QuickLook
import SwiftUI

/// The Reports screen, pushed from the Statistics title menu: what a PDF report holds, and "Create report". The choices
/// are kept (`ReportPreferences`); the finished file opens in the preview (share, print and save come with it).
struct ReportsScreen: View {
    /// not observed: its pages' bookkeeping and Close only
    let state: Stat.StateModel
    @ObservedObject var exporter: Stat.ReportExporter

    @State private var options: ReportOptions

    private var preferences: ReportPreferences { exporter.preferences }

    init(state: Stat.StateModel, exporter: Stat.ReportExporter) {
        self.state = state
        self.exporter = exporter
        _options = State(initialValue: exporter.preferences.options(userUnits: state.settings.units))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatsCard { layout }
                StatsCard { parts }
                StatsCard { create }
            }
            .statsPageContent()
        }
        .statsPage(title: NSLocalizedString("Reports", comment: "Statistics: the PDF reports screen, and its menu item"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { state.hideModal() }
            }
        }
        .background(ReportPreviewHost(exporter: exporter, screen: true))
        .onAppear { state.appear(.reports) }
        .onDisappear {
            if exporter.running == .screen {
                exporter.cancel()
            }
            state.disappear(.reports)
        }
    }

    // MARK: - Period, units, paper

    @ViewBuilder private var layout: some View {
        VStack(alignment: .leading, spacing: 6) {
            title("Period")
            PeriodPicker(
                periods: ReportOptions.periods,
                selection: Binding(get: { options.period }, set: { period in
                    options.period = period
                    preferences.period = period
                    exporter.clearFailure()
                })
            )
        }
        VStack(alignment: .leading, spacing: 6) {
            title("Units")
            StatsSegmentedControl(
                items: ReportUnits.allCases,
                selection: Binding(get: { options.units }, set: { units in
                    options.units = units
                    preferences.units = units
                }),
                label: { Self.label($0) }
            )
        }
        VStack(alignment: .leading, spacing: 6) {
            title("Paper")
            StatsSegmentedControl(
                items: ReportPaper.allCases,
                selection: Binding(get: { options.paper }, set: { paper in
                    options.paper = paper
                    preferences.paper = paper
                }),
                label: { Self.label($0) }
            )
        }
    }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    static func label(_ units: ReportUnits) -> String {
        switch units {
        case .mgdL: return GlucoseUnits.mgdL.rawValue
        case .mmolL: return GlucoseUnits.mmolL.rawValue
        case .both: return NSLocalizedString("Both", comment: "Reports screen: the report in mg/dL and in mmol/L")
        }
    }

    static func label(_ paper: ReportPaper) -> String {
        switch paper {
        case .a4: return NSLocalizedString("A4", comment: "Reports screen: the paper size")
        case .letter: return NSLocalizedString("US Letter", comment: "Reports screen: the paper size")
        }
    }

    // MARK: - Parts

    @ViewBuilder private var parts: some View {
        Text("Contents")
            .statsSectionTitle()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ReportPart.implemented.enumerated()), id: \.element) { index, part in
                if index > 0 {
                    Divider()
                }
                partRow(part)
                if options.parts.contains(part), part.hasSettings {
                    settings(of: part)
                        .padding(.leading, 34)
                        .padding(.bottom, 6)
                }
            }
        }
    }

    private func partRow(_ part: ReportPart) -> some View {
        let isSelected = options.parts.contains(part)
        return Button {
            if isSelected {
                options.parts.remove(part)
            } else {
                options.parts.insert(part)
            }
            preferences.parts = options.parts
            exporter.clearFailure()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)
                Text(part.title)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func settings(of part: ReportPart) -> some View {
        if part == .summary {
            Toggle(
                "Insulin and carbs per day",
                isOn: Binding(get: { options.summary.insulinAndCarbs }, set: { isOn in
                    options.summary.insulinAndCarbs = isOn
                    preferences.summaryInsulinAndCarbs = isOn
                })
            )
            .font(.subheadline)
            .frame(minHeight: 40)
            Toggle(
                "Glycemia Risk Index",
                isOn: Binding(get: { options.summary.gri }, set: { isOn in
                    options.summary.gri = isOn
                    preferences.summaryGRI = isOn
                })
            )
            .font(.subheadline)
            .frame(minHeight: 40)
        } else if part == .daysTable {
            daysToggle("Insulin", \.insulin)
            daysToggle("Carbs", \.carbs)
            daysToggle("SD and CV", \.sdAndCV)
            daysToggle("Lowest and highest", \.lowestAndHighest)
            daysToggle("CGM coverage", \.cgmCoverage)
            daysToggle("Newest first", \.newestFirst)
            VStack(alignment: .leading, spacing: 6) {
                title("Subtotals")
                StatsSegmentedControl(
                    items: ReportOptions.DaysTableSettings.Subtotals.allCases,
                    selection: Binding(get: { options.daysTable.subtotals }, set: { subtotals in
                        options.daysTable.subtotals = subtotals
                        preferences.daysTable = options.daysTable
                    }),
                    label: { Self.label($0) }
                )
            }
            .padding(.top, 4)
        } else if part == .dailyCharts {
            VStack(alignment: .leading, spacing: 6) {
                title("Days per page")
                StatsSegmentedControl(
                    items: ReportOptions.DailyChartsSettings.daysPerPageChoices,
                    selection: Binding(get: { options.dailyCharts.daysPerPage }, set: { days in
                        options.dailyCharts.daysPerPage = days
                        preferences.dailyCharts = options.dailyCharts
                    }),
                    label: { "\($0)" }
                )
            }
            chartsToggle("Boluses and SMBs", \.boluses)
            chartsToggle("Carbs", \.carbs)
            chartsToggle("Basal", \.basal)
            chartsToggle("Newest first", \.newestFirst)
        }
    }

    private func daysToggle(
        _ title: LocalizedStringKey,
        _ setting: WritableKeyPath<ReportOptions.DaysTableSettings, Bool>
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(get: { options.daysTable[keyPath: setting] }, set: { isOn in
                options.daysTable[keyPath: setting] = isOn
                preferences.daysTable = options.daysTable
            })
        )
        .font(.subheadline)
        .frame(minHeight: 40)
    }

    private func chartsToggle(
        _ title: LocalizedStringKey,
        _ setting: WritableKeyPath<ReportOptions.DailyChartsSettings, Bool>
    ) -> some View {
        Toggle(
            title,
            isOn: Binding(get: { options.dailyCharts[keyPath: setting] }, set: { isOn in
                options.dailyCharts[keyPath: setting] = isOn
                preferences.dailyCharts = options.dailyCharts
            })
        )
        .font(.subheadline)
        .frame(minHeight: 40)
    }

    static func label(_ subtotals: ReportOptions.DaysTableSettings.Subtotals) -> String {
        switch subtotals {
        case .none: return NSLocalizedString("None", comment: "")
        case .week: return NSLocalizedString("Week", comment: "")
        case .month: return NSLocalizedString("Month", comment: "")
        }
    }

    // MARK: - Create

    @ViewBuilder private var create: some View {
        Text(Self.pages(options.estimatedPageCount, upTo: options.estimateIsUpperBound))
            .font(.subheadline)
        Text("The report contains glucose and insulin data.")
            .statsNote()
        if exporter.running == .screen {
            HStack(spacing: 12) {
                ProgressView(value: exporter.progress)
                Button("Cancel") { exporter.cancel() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        } else {
            Button {
                exporter.export(options)
            } label: {
                Text("Create report")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(options.parts.isEmpty ? Color.secondary : Color.accentColor)
            .disabled(options.parts.isEmpty || exporter.isRunning)
        }
        if let failure = exporter.failure(at: .screen) {
            Text(failure)
                .statsNote()
        }
    }

    /// "2 pages", "1 page", "Nothing selected"; "Up to 7 pages" when the count is an upper bound
    /// (`ReportOptions.estimateIsUpperBound`)
    static func pages(_ count: Int, upTo: Bool = false) -> String {
        switch count {
        case 0: return NSLocalizedString("Nothing selected", comment: "Reports screen: no part is selected")
        case 1: return NSLocalizedString("1 page", comment: "Reports screen: the report's estimated pages")
        default: return String(
                format: upTo
                    ? NSLocalizedString("Up to %d pages", comment: "Reports screen: the most pages the report can have")
                    : NSLocalizedString("%d pages", comment: "Reports screen: the report's estimated pages"),
                count
            )
        }
    }
}

/// Presents the finished report of its side (the Reports screen's, or the views' own) in the preview. A view of its
/// own behind the page, so only it is redrawn when a report is ready, not the page.
struct ReportPreviewHost: View {
    @ObservedObject var exporter: Stat.ReportExporter
    /// the Reports screen's presenter; false: the root's, for the views' "Export PDF"
    let screen: Bool

    var body: some View {
        Color.clear
            .quickLookPreview(exporter.previewBinding(screen: screen))
    }
}

/// "Export PDF" at the bottom of a Statistics view: that view's part of the report alone, for the period on screen,
/// straight to the preview. Outside Statistics (no exporter in the environment) it shows nothing.
struct ReportExportButton: View {
    let part: ReportPart
    /// Daily charts of this day alone (the Day view's); nil: the period on screen
    var day: Date?

    @Environment(\.reportExporter) private var exporter

    var body: some View {
        if let exporter {
            Content(part: part, day: day, exporter: exporter)
        }
    }

    private struct Content: View {
        let part: ReportPart
        let day: Date?
        @ObservedObject var exporter: Stat.ReportExporter

        var body: some View {
            let origin = Stat.ReportOrigin.part(part)
            VStack(spacing: 6) {
                Button {
                    exporter.export(part: part, day: day)
                } label: {
                    HStack(spacing: 8) {
                        if exporter.running == origin {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.footnote.weight(.bold))
                        }
                        Text("Export PDF")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(exporter.isRunning)
                if let failure = exporter.failure(at: origin) {
                    Text(failure)
                        .statsNote()
                }
            }
        }
    }
}
