import Charts
import CoreData
import SwiftUI

// MARK: - Popover Data

private struct PopoverData: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let color: Color
    let items: [(label: String, value: String)]
    let origin: CardPosition

    static func == (lhs: PopoverData, rhs: PopoverData) -> Bool { lhs.id == rhs.id }
}

private enum CardPosition {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

// MARK: - Overview Grid

struct StatOverviewView: View {
    @ObservedObject var state: Stat.StateModel
    @Environment(\.colorScheme) var colorScheme

    private let todayFilter = Calendar.current.startOfDay(for: Date()) as NSDate
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    @State private var activePopover: PopoverData?

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                LazyVGrid(columns: columns, spacing: 12) {
                    OverviewGlucoseCard(
                        filter: todayFilter,
                        highLimit: state.highLimit,
                        lowLimit: state.lowLimit,
                        units: state.units,
                        navigate: { state.selectedView = .glucose },
                        showPopover: { newPopover in
                            if activePopover?.origin == newPopover.origin {
                                activePopover = nil
                            } else {
                                activePopover = newPopover
                            }
                        }
                    )

                    OverviewLoopingCard(
                        filter: todayFilter,
                        navigate: { state.selectedView = .looping },
                        showPopover: { newPopover in
                            if activePopover?.origin == newPopover.origin {
                                activePopover = nil
                            } else {
                                activePopover = newPopover
                            }
                        }
                    )

                    OverviewInsulinCard(
                        todayBolus: todayBolus,
                        todayBasal: todayBasal,
                        averageTDD: state.tddActualAverage,
                        tddYesterday: state.tddYesterday,
                        tdd2DaysAgo: state.tdd2DaysAgo,
                        tdd3DaysAgo: state.tdd3DaysAgo,
                        navigate: { state.selectedView = .insulin },
                        showPopover: { newPopover in
                            if activePopover?.origin == newPopover.origin {
                                activePopover = nil
                            } else {
                                activePopover = newPopover
                            }
                        }
                    )

                    OverviewMealCard(
                        mealStats: todayMealStats,
                        navigate: { state.selectedView = .meals },
                        showPopover: { newPopover in
                            if activePopover?.origin == newPopover.origin {
                                activePopover = nil
                            } else {
                                activePopover = newPopover
                            }
                        }
                    )
                }

                HStack {
                    Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                    Text(NSLocalizedString(
                        "Tap a ring for details. Tap a card to open the full view.",
                        comment: "Overview screen hint"
                    ))
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .padding(.top, 4)
            }
            .opacity(activePopover != nil ? 0.3 : 1.0)

            // Diagonal popover overlay
            if let popover = activePopover {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { activePopover = nil } }

                OverviewPopoverView(data: popover)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { activePopover = nil } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: popoverAlignment(for: popover.origin))
                    .padding(20)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: activePopover)
    }

    private func popoverAlignment(for origin: CardPosition) -> Alignment {
        switch origin {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private var todayBolusStats: BolusStats? {
        let today = Calendar.current.startOfDay(for: Date())
        return state.dailyBolusStats.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
    }

    private var todayBolus: Double { todayBolusStats?.manualBolus ?? 0 }
    private var todayBasal: Double { todayBolusStats?.external ?? 0 }

    private var todayMealStats: MealStats? {
        let today = Calendar.current.startOfDay(for: Date())
        return state.dailyMealStats.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
    }
}

// MARK: - Popover Overlay View

private struct OverviewPopoverView: View {
    let data: PopoverData
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(data.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(data.color)

            ForEach(Array(data.items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Text(item.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.value)
                        .fontWeight(.semibold)
                }
                .font(.system(size: 15, design: .rounded))
            }
        }
        .padding(18)
        .frame(minWidth: 220, maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(data.color.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - Mini Card Container

private struct MiniCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    let navigate: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }

            content()
        }
        .padding(14)
        .elegantShadow(scheme: colorScheme)
        .contentShape(Rectangle())
        .onTapGesture { navigate() }
    }
}

// MARK: - Interactive Donut (only this triggers popover)

private struct InteractiveDonut<C: View>: View {
    let showPopover: () -> Void
    @ViewBuilder let chart: () -> C

    var body: some View {
        chart()
            .chartLegend(.hidden)
            .frame(width: 113, height: 113)
            .contentShape(Circle())
            .onTapGesture { showPopover() }
            .highPriorityGesture(TapGesture().onEnded { showPopover() })
    }
}

// MARK: - No Data Placeholder

private struct MiniNoData: View {
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(color.opacity(0.3))
            Text(NSLocalizedString("No Data", comment: ""))
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Glucose Card

private struct OverviewGlucoseCard: View {
    @FetchRequest var readings: FetchedResults<Readings>
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let navigate: () -> Void
    let showPopover: (PopoverData) -> Void

    private let conversionFactor = 0.0555

    init(
        filter: NSDate, highLimit: Decimal, lowLimit: Decimal, units: GlucoseUnits,
        navigate: @escaping () -> Void, showPopover: @escaping (PopoverData) -> Void
    ) {
        _readings = FetchRequest<Readings>(
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "glucose > 0 AND date > %@", filter)
        )
        self.highLimit = highLimit
        self.lowLimit = lowLimit
        self.units = units
        self.navigate = navigate
        self.showPopover = showPopover
    }

    var body: some View {
        let total = readings.count
        let highCount = readings.filter { $0.glucose > Int(highLimit) }.count
        let lowCount = readings.filter { $0.glucose < Int(lowLimit) }.count
        let inRangeCount = total - highCount - lowCount
        let tirPercent = total > 0 ? Double(inRangeCount) / Double(total) * 100 : 0
        let avgGlucose = total > 0
            ? Double(readings.map { Int($0.glucose) }.reduce(0, +)) / Double(total)
            : 0

        MiniCard(
            title: NSLocalizedString("Glucose", comment: ""),
            icon: "drop.fill",
            color: Color.loopGreen,
            navigate: navigate
        ) {
            if total > 0 {
                InteractiveDonut(showPopover: {
                    showPopover(glucosePopoverData(
                        total: total, highCount: highCount, inRangeCount: inRangeCount, lowCount: lowCount
                    ))
                }) {
                    Chart {
                        SectorMark(
                            angle: .value("High", highCount),
                            innerRadius: .ratio(0.618),
                            outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.loopYellow).cornerRadius(4)
                        SectorMark(
                            angle: .value("In Range", inRangeCount),
                            innerRadius: .ratio(0.618),
                            outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.loopGreen).cornerRadius(4)
                        SectorMark(
                            angle: .value("Low", lowCount),
                            innerRadius: .ratio(0.618),
                            outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.loopRed).cornerRadius(4)
                    }
                }

                VStack(spacing: 3) {
                    Text(tirPercent.formatted(.number.precision(.fractionLength(1))) + "%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("Time in Range", comment: ""))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text("Ø " + formatGlucose(avgGlucose) + " " + units.rawValue)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                MiniNoData(icon: "drop.fill", color: Color.loopGreen)
            }
        }
    }

    private func glucosePopoverData(total: Int, highCount: Int, inRangeCount: Int, lowCount: Int) -> PopoverData {
        let totalD = Double(total)
        let tight = readings.filter { $0.glucose >= 70 && $0.glucose <= 140 }.count
        let veryHigh = readings.filter { $0.glucose > 250 }.count
        let veryLow = readings.filter { $0.glucose <= 54 }.count

        let values = readings.map { Int($0.glucose) }
        let avg = totalD > 0 ? Double(values.reduce(0, +)) / totalD : 0
        let median = StatChartUtils.medianCalculation(array: values)

        return PopoverData(
            title: NSLocalizedString("Glucose Details", comment: ""),
            color: Color.loopGreen,
            items: [
                (
                    NSLocalizedString("High", comment: "") + " (>\(formatGlucoseDecimal(highLimit)))",
                    fmtPct(Double(highCount) / totalD * 100)
                ),
                (
                    NSLocalizedString("Very High", comment: "") + " (>250)",
                    fmtPct(Double(veryHigh) / totalD * 100)
                ),
                (
                    NSLocalizedString("In Range", comment: ""),
                    fmtPct(Double(inRangeCount) / totalD * 100)
                ),
                (
                    NSLocalizedString("Tight", comment: "") + " (70–140)",
                    fmtPct(Double(tight) / totalD * 100)
                ),
                (
                    NSLocalizedString("Low", comment: "") + " (<\(formatGlucoseDecimal(lowLimit)))",
                    fmtPct(Double(lowCount) / totalD * 100)
                ),
                (
                    NSLocalizedString("Very Low", comment: "") + " (<54)",
                    fmtPct(Double(veryLow) / totalD * 100)
                ),
                (NSLocalizedString("Average", comment: ""), formatGlucose(avg)),
                (NSLocalizedString("Median", comment: ""), formatGlucose(median))
            ],
            origin: .topLeft
        )
    }

    private func formatGlucose(_ value: Double) -> String {
        StatChartUtils.formatGlucose(value, units: units)
    }

    private func formatGlucoseDecimal(_ value: Decimal) -> String {
        StatChartUtils.formatGlucoseDecimal(value, units: units)
    }

    private func fmtPct(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

// MARK: - Insulin Card

private struct OverviewInsulinCard: View {
    let todayBolus: Double
    let todayBasal: Double
    let averageTDD: Decimal
    let tddYesterday: Decimal
    let tdd2DaysAgo: Decimal
    let tdd3DaysAgo: Decimal
    let navigate: () -> Void
    let showPopover: (PopoverData) -> Void

    var body: some View {
        let todayTDD = todayBolus + todayBasal
        let avg = Double(truncating: averageTDD as NSDecimalNumber)
        let hasData = avg > 0 || todayTDD > 0

        MiniCard(
            title: NSLocalizedString("Insulin", comment: ""),
            icon: "syringe.fill",
            color: Color.insulin,
            navigate: navigate
        ) {
            if hasData {
                InteractiveDonut(showPopover: {
                    showPopover(PopoverData(
                        title: NSLocalizedString("Insulin Details", comment: ""),
                        color: Color.insulin,
                        items: [
                            (NSLocalizedString("Bolus", comment: ""), fmtU(todayBolus)),
                            (NSLocalizedString("Basal", comment: ""), fmtU(todayBasal)),
                            (NSLocalizedString("Yesterday", comment: ""), fmtUDec(tddYesterday)),
                            (NSLocalizedString("2 Days Ago", comment: ""), fmtUDec(tdd2DaysAgo)),
                            (NSLocalizedString("3 Days Ago", comment: ""), fmtUDec(tdd3DaysAgo)),
                            (NSLocalizedString("Ø 10 Days", comment: ""), fmtUDec(averageTDD))
                        ],
                        origin: .bottomLeft
                    ))
                }) {
                    Chart {
                        SectorMark(
                            angle: .value("Bolus", max(todayBolus, 0.001)),
                            innerRadius: .ratio(0.618), outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.insulin).cornerRadius(4)
                        SectorMark(
                            angle: .value("Basal", max(todayBasal, 0.001)),
                            innerRadius: .ratio(0.618), outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.lightBlue).cornerRadius(4)
                    }
                }

                VStack(spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(fmtDbl(todayTDD))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                        Text(NSLocalizedString("U", comment: "Unit"))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Text(NSLocalizedString("Today", comment: ""))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text("Ø " + fmtDbl(avg) + " U")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                MiniNoData(icon: "syringe.fill", color: Color.insulin)
            }
        }
    }

    private func fmtU(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " U"
    }

    private func fmtUDec(_ value: Decimal) -> String {
        Double(truncating: value as NSDecimalNumber).formatted(.number.precision(.fractionLength(1))) + " U"
    }

    private func fmtDbl(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Looping Card

private struct OverviewLoopingCard: View {
    @FetchRequest var loopRecords: FetchedResults<LoopStatRecord>
    let navigate: () -> Void
    let showPopover: (PopoverData) -> Void

    init(filter: NSDate, navigate: @escaping () -> Void, showPopover: @escaping (PopoverData) -> Void) {
        _loopRecords = FetchRequest<LoopStatRecord>(
            sortDescriptors: [NSSortDescriptor(key: "start", ascending: false)],
            predicate: NSPredicate(format: "start > %@", filter)
        )
        self.navigate = navigate
        self.showPopover = showPopover
    }

    var body: some View {
        let loopStatuses = loopRecords.compactMap(\.loopStatus)
        let total = loopStatuses.count
        let successful = loopStatuses.filter { $0.contains("Success") }.count
        let failed = total - successful
        let successPercent = total > 0 ? Double(successful) / Double(total) * 100 : 0
        let badgeColor: Color = successPercent >= 95 ? Color.loopGreen :
            (successPercent >= 85 ? Color.loopYellow : Color.loopRed)

        let durationArray = loopRecords.compactMap(\.duration)
        let medianDuration = StatChartUtils.medianCalculationDouble(array: durationArray) * 60
        let intervalArray = loopRecords.compactMap(\.interval).filter { $0 > 0 }
        let medianInterval = StatChartUtils.medianCalculationDouble(array: intervalArray) * 60

        MiniCard(
            title: NSLocalizedString("Looping", comment: ""),
            icon: "arrow.triangle.2.circlepath",
            color: Color.purple,
            navigate: navigate
        ) {
            if total > 0 {
                InteractiveDonut(showPopover: {
                    showPopover(PopoverData(
                        title: NSLocalizedString("Loop Details", comment: ""),
                        color: Color.purple,
                        items: [
                            (NSLocalizedString("Successful", comment: ""), "\(successful)"),
                            (NSLocalizedString("Failed", comment: ""), "\(failed)"),
                            (
                                NSLocalizedString("Interval", comment: ""),
                                (medianInterval / 60).formatted(.number.precision(.fractionLength(1))) + " min"
                            ),
                            (
                                NSLocalizedString("Duration", comment: ""),
                                medianDuration.formatted(.number.precision(.fractionLength(1))) + " s"
                            )
                        ],
                        origin: .topRight
                    ))
                }) {
                    Chart {
                        SectorMark(
                            angle: .value("Successful", successful),
                            innerRadius: .ratio(0.618), outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.purple).cornerRadius(4)
                        SectorMark(
                            angle: .value("Failed", max(failed, 0)),
                            innerRadius: .ratio(0.618), outerRadius: .ratio(0.88),
                            angularInset: 1.5
                        )
                        .foregroundStyle(Color.purple.opacity(0.35)).cornerRadius(4)
                    }
                }

                VStack(spacing: 3) {
                    Text(
                        (successPercent / 100).formatted(.percent.precision(.fractionLength(1)))
                    )
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    Text(NSLocalizedString("Success", comment: ""))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                Text("\(successful) " + NSLocalizedString("Loops", comment: ""))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                MiniNoData(icon: "arrow.triangle.2.circlepath", color: Color.purple)
            }
        }
    }
}

// MARK: - Meals Card

private struct OverviewMealCard: View {
    let mealStats: MealStats?
    let navigate: () -> Void
    let showPopover: (PopoverData) -> Void

    var body: some View {
        let stats = mealStats
        let hasData = stats.map { $0.carbs + $0.fat + $0.protein > 0 } ?? false

        MiniCard(
            title: NSLocalizedString("Meals", comment: ""),
            icon: "fork.knife",
            color: Color.loopYellow,
            navigate: navigate
        ) {
            if let stats, hasData {
                let total = stats.carbs + stats.fat + stats.protein
                let kcal = stats.carbs * 4 + stats.protein * 4 + stats.fat * 9
                let sections = mealSections(stats)

                InteractiveDonut(showPopover: {
                    showPopover(PopoverData(
                        title: NSLocalizedString("Meal Details", comment: ""),
                        color: Color.loopYellow,
                        items: mealPopoverItems(stats: stats, total: total, kcal: kcal),
                        origin: .bottomRight
                    ))
                }) {
                    Chart {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            SectorMark(
                                angle: .value("Macro", section.value),
                                innerRadius: .ratio(0.618), outerRadius: .ratio(0.88),
                                angularInset: 1.0
                            )
                            .foregroundStyle(section.color)
                            .cornerRadius(3)
                        }
                    }
                }

                VStack(spacing: 3) {
                    Text(kcal.formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        + Text(" kcal")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("Today", comment: ""))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }

                HStack(spacing: 8) {
                    macroDot(color: Color.loopYellow, value: stats.carbs, total: total)
                    if stats.fat > 0 { macroDot(color: Color.loopRed, value: stats.fat, total: total) }
                    if stats.protein > 0 { macroDot(color: Color.purple, value: stats.protein, total: total) }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
            } else {
                MiniNoData(icon: "fork.knife", color: Color.loopYellow)
            }
        }
    }

    private func mealSections(_ stats: MealStats) -> [(value: Double, color: Color)] {
        var result: [(value: Double, color: Color)] = [(.init(stats.carbs), Color.loopYellow)]
        if stats.fat > 0 { result.append((.init(stats.fat), Color.loopRed)) }
        if stats.protein > 0 { result.append((.init(stats.protein), Color.purple)) }
        return result
    }

    private func mealPopoverItems(stats: MealStats, total: Double, kcal: Double) -> [(label: String, value: String)] {
        [
            (NSLocalizedString("Carbs", comment: ""), fmtG(stats.carbs) + pct(stats.carbs, total)),
            (NSLocalizedString("Fat", comment: ""), fmtG(stats.fat) + pct(stats.fat, total)),
            (NSLocalizedString("Protein", comment: ""), fmtG(stats.protein) + pct(stats.protein, total)),
            (NSLocalizedString("Calories", comment: ""), kcal.formatted(.number.precision(.fractionLength(0))) + " kcal")
        ]
    }

    private func fmtG(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0))) + " g"
    }

    private func pct(_ value: Double, _ total: Double) -> String {
        guard total > 0 else { return "" }
        return " (" + (value / total * 100).formatted(.number.precision(.fractionLength(0))) + "%)"
    }

    private func macroDot(color: Color, value: Double, total: Double) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text((value / total * 100).formatted(.number.precision(.fractionLength(0))) + "%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
