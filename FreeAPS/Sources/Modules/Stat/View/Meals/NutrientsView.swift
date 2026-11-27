import SwiftUI

// MARK: - The screens

/// The Nutrients screen, pushed from the Meals tab's Carbs card: every nutrient per day against its reference intake.
/// A row pushes that nutrient's screen.
struct NutrientsScreen: View {
    @ObservedObject var state: Stat.StateModel

    @State private var opened: StatsNutrient?
    /// the Reference intakes sheet, from the note without references
    @State private var isReferencesSheetShown = false

    var body: some View {
        NutrientsPage(
            state: state,
            page: .nutrients,
            title: NSLocalizedString("Nutrients", comment: "Statistics Nutrients: the title")
        ) {
            StatsContentView(
                content: state.mealsContent,
                emptyText: "No carb entries in this period",
                failedText: "The carb entries couldn't be read."
            ) { meals in
                NutrientsCard(
                    nutrients: meals.nutrients,
                    open: { opened = $0 },
                    setReferences: { isReferencesSheetShown = true }
                )
            }
        }
        .navigationDestination(item: $opened) { nutrient in
            NutrientScreen(state: state, nutrient: nutrient)
        }
        .sheet(isPresented: $isReferencesSheetShown) {
            ReferenceIntakesSheet(settingsManager: state.settingsManager, settings: state.appCoordinator.settings.value)
        }
    }
}

/// One nutrient's screen, pushed from the Nutrients screen: day by day, and the selected day's entries.
private struct NutrientScreen: View {
    @ObservedObject var state: Stat.StateModel
    let nutrient: StatsNutrient

    var body: some View {
        NutrientsPage(state: state, page: .nutrient, title: Stat.Nutrients.name(nutrient)) {
            StatsContentView(
                content: state.mealsContent,
                emptyText: "No carb entries in this period",
                failedText: "The carb entries couldn't be read."
            ) { meals in
                NutrientDetailView(
                    nutrients: meals.nutrients,
                    nutrient: nutrient,
                    selection: state.nutrientDaySelection,
                    showToday: { state.showToday() }
                )
            }
        }
    }
}

/// A page pushed inside Statistics: the Meals tab's period control over its content, the root's look and Close. It
/// counts as Statistics on screen (`StateModel.appear`): pushing or popping it neither closes the session nor reads
/// again, coming back from the background while it is shown reads the Meals tab again.
private struct NutrientsPage<Content: View>: View {
    @ObservedObject var state: Stat.StateModel
    let page: Stat.StateModel.Page
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            PeriodPicker(
                periods: state.validPeriods,
                selection: Binding(get: { state.period }, set: { state.select(period: $0) })
            )
            .padding(.horizontal, 12)
            .padding(.top, 4)
            ScrollView {
                content
                    .statsPageContent()
            }
        }
        .statsPage(title: title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", action: state.hideModal)
            }
        }
        .onAppear { state.appear(page) }
        .onDisappear { state.disappear(page) }
    }
}

// MARK: - Per day

/// "Per day": the coverage with the limited mark, then every nutrient (sorted by the share of its reference, or grouped
/// without references, salt then the only one with a bar), the legend and what the percentages compare with. On Today
/// "So far": today's entries' nutrients against the daily references, the same rows.
private struct NutrientsCard: View {
    let nutrients: Stat.Nutrients
    let open: (StatsNutrient) -> Void
    /// the note without references: opens the Reference intakes sheet
    let setReferences: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var sections: [Stat.Nutrients.NutrientSection] { nutrients.today?.sections ?? nutrients.sections }
    private var emptyTitle: String? { nutrients.today.map(\.emptyTitle) ?? nutrients.emptyTitle }
    private var basis: String? { nutrients.today.map(\.basis) ?? nutrients.basis }
    /// Today has no average to be provisional
    private var limitedNote: String? { nutrients.today == nil ? nutrients.limitedNote : nil }

    var body: some View {
        StatsCard {
            VStack(alignment: .leading, spacing: 4) {
                if let today = nutrients.today {
                    StatsCardHeader(title: "So far", range: today.dateRange)
                } else {
                    StatsCardHeader(title: "Per day", range: nutrients.dateRange)
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text(nutrients.today?.coverage ?? nutrients.coverage)
                        .statsFootnote()
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                    if let note = limitedNote {
                        LimitedDataMarker(note: note, font: .footnote)
                    }
                }
            }

            if let title = emptyTitle {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline)
                    Text(
                        "Foods added from food search or a preset carry fiber, vitamins and minerals. Carbs entered as a number don't."
                    )
                    .statsFootnote()
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if !nutrients.hasReferences {
                    noReferences
                }
                rows
                legend
                if let basis {
                    Text(basis)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var noReferences: some View {
        Button(action: setReferences) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Stat.Nutrients.noReferencesNote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
            }
            .font(.footnote)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private var rows: some View {
        // stacked at the larger text sizes (the tiles' threshold)
        let large = dynamicTypeSize > .large
        return VStack(spacing: 0) {
            ForEach(sections) { section in
                if let title = section.title {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
                StatsDividedRows(section.rows) { row in
                    NutrientRowView(row: row, large: large) { open(row.nutrient) }
                }
            }
        }
    }

    private var legend: some View {
        StatsFlowLayout(horizontalSpacing: 14, verticalSpacing: 4) {
            HStack(spacing: 6) {
                NutrientBarView(bar: Stat.Nutrients.Bar(filled: 0.5, over: 0), tickOverhang: 3)
                    .frame(width: 18)
                Text(nutrients.legendTick)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.statsWarning))
                    .frame(width: 12, height: 4)
                Text("Above the salt limit")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A nutrient's row: the name (its other name, or salt's excess, under it), the amount, the percent, the bar under them;
/// stacked at the larger text sizes. A tap opens the nutrient.
private struct NutrientRowView: View {
    let row: Stat.Nutrients.Row
    let large: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Group {
                if large {
                    stacked
                } else {
                    regular
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var regular: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.name)
                        .font(.subheadline)
                    subtitle
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.amount)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                if let percent = row.percent {
                    Text(percent)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.isOverLimit ? Color(.statsWarning) : Color.primary)
                        .lineLimit(1)
                        .frame(minWidth: 46, alignment: .trailing)
                }
                chevron
            }
            if let bar = row.bar {
                // under the name, the amount and the percent: not under the chevron
                NutrientBarView(bar: bar)
                    .padding(.trailing, 20)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 48)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.name)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                chevron
            }
            subtitle
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.amount)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let percent = row.percent {
                    Text(percent)
                        .fontWeight(.semibold)
                        .foregroundStyle(row.isOverLimit ? Color(.statsWarning) : Color.primary)
                }
            }
            .font(.body)
            .monospacedDigit()
            if let bar = row.bar {
                NutrientBarView(bar: bar, height: 6)
            }
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var subtitle: some View {
        if let subtitle = row.subtitle {
            Text(subtitle)
                .font(large ? .subheadline : .caption)
                .foregroundStyle(row.isOverLimit ? Color(.statsWarning) : Color.secondary)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
    }
}

/// The 0–150% bar: the track, the amount, salt's excess in orange from the 100% tick, the tick.
private struct NutrientBarView: View {
    let bar: Stat.Nutrients.Bar
    var height: CGFloat = 4
    /// the tick's reach above and below the bar
    var tickOverhang: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let radius = height / 2
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color(.systemGray5))
                RoundedRectangle(cornerRadius: radius)
                    .fill(Color(.statsNutrient))
                    .frame(width: width * bar.filled)
                if bar.over > 0 {
                    UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: radius, topTrailing: radius))
                        .fill(Color(.statsWarning))
                        .frame(width: width * bar.over)
                        .offset(x: width * Stat.Nutrients.Bar.tick)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary)
                    .frame(width: 2, height: height + 2 * tickOverhang)
                    .offset(x: width * Stat.Nutrients.Bar.tick - 1)
            }
            // the bar's height, centered: the tick overhangs both ways, not only below (a GeometryReader puts its content at the top)
            .frame(width: width, height: height, alignment: .leading)
        }
        .frame(height: height)
    }
}

// MARK: - One nutrient

/// A nutrient's average and its share of the reference, the day chart, and the selected day's card; on Today, today's
/// amount so far against the reference and today's entries.
private struct NutrientDetailView: View {
    let nutrients: Stat.Nutrients
    let nutrient: StatsNutrient
    let selection: DailySelection
    /// "Show Today": the Today period
    let showToday: () -> Void

    var body: some View {
        if let today = nutrients.today, let detail = nutrients.todayDetail(nutrient) {
            todayView(detail, dateRange: today.dateRange)
        } else {
            daysView
        }
    }

    /// Today: no chart and no stepper (one day); today's coverage (the Nutrients screen's), not the period chart's day
    /// status.
    private func todayView(_ detail: Stat.Nutrients.TodayDetail, dateRange: String) -> some View {
        let card = detail.card
        return StatsCard {
            StatsCardHeader(verbatim: detail.name, range: dateRange)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(card.amount)
                        .font(.title.bold())
                        .monospacedDigit()
                    Text(card.unit)
                        .font(.subheadline.weight(.semibold))
                    Text("so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let reference = detail.reference {
                    Text(reference)
                        .font(.subheadline)
                        .foregroundStyle(card.isOverLimit ? Color(.statsWarning) : Color.secondary)
                }
                Text(detail.coverage)
                    .statsFootnote()
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            entryList(card.entries)
        }
    }

    @ViewBuilder private var daysView: some View {
        let detail = nutrients.detail(nutrient)
        let days = detail.plot.dayIntervals
        let index = selection.index(in: days)
        let card = index.map { nutrients.card(at: $0, for: nutrient) }
        VStack(spacing: 16) {
            StatsCard {
                VStack(alignment: .leading, spacing: 4) {
                    StatsCardHeader(verbatim: detail.name, range: nutrients.dateRange)
                    Text(nutrients.coverage)
                        .statsFootnote()
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let average = detail.average {
                    VStack(alignment: .leading, spacing: 2) {
                        StatsHeadlineNumber(
                            value: average,
                            unit: detail.unit,
                            caption: NSLocalizedString("per day", comment: "Statistics: the unit of a daily time or count"),
                            limitedNote: nutrients.limitedNote
                        )
                        if let reference = detail.reference {
                            Text(reference)
                                .font(.subheadline)
                                .foregroundStyle(detail.isOverLimit ? Color(.statsWarning) : Color.secondary)
                        }
                    }
                } else {
                    Text(Stat.Nutrients.noCountedDay)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let index {
                    StatsDayBarsChart(plot: detail.plot, selected: index, selection: selection)
                }
                StatsChartLegend(items: detail.legend)
            }

            if let index, let card {
                StatsCard { dayCard(card, index: index, days: days) }
            }
        }
    }

    @ViewBuilder private func dayCard(_ card: Stat.Nutrients.DayCard, index: Int, days: [DateInterval]) -> some View {
        StatsStepper(title: card.title, index: index, count: days.count) { selection.pick($0, in: days) }

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(card.amount)
                    .font(.title.bold())
                    .monospacedDigit()
                Text(card.unit)
                    .font(.subheadline.weight(.semibold))
                if card.soFar {
                    Text("so far")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let percent = card.percent {
                    Text(percent)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(card.isOverLimit ? Color(.statsWarning) : Color.secondary)
                }
            }
            Text(card.status)
                .statsNote()
        }

        entryList(card.entries)

        // today has the Today period's view
        if nutrients.days.indices.contains(index), nutrients.days[index].isToday {
            StatsShowTodayButton(action: showToday)
        }
    }

    /// The day's entries with the nutrient's amount in each.
    @ViewBuilder private func entryList(_ entries: [Stat.Nutrients.Entry]) -> some View {
        if entries.isNotEmpty {
            VStack(spacing: 0) {
                StatsDividedRows(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(entry.time)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        if let carbs = entry.carbs {
                            Text(carbs)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .fixedSize()
                        }
                        Text(entry.value)
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(entry.isListed ? Color.primary : Color.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(minHeight: 40)
                }
            }
        }
    }
}
