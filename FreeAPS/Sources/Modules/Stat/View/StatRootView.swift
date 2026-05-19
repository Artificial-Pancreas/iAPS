import Charts
import CoreData
import SwiftDate
import SwiftUI
import Swinject

extension Stat {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel
        @Environment(\.colorScheme) var colorScheme

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            VStack(spacing: 0) {
                // Top category picker
                Picker(NSLocalizedString("View", comment: "Statistics view picker label"), selection: $state.selectedView) {
                    ForEach(StatisticViewType.allCases) { viewType in
                        Text(viewType.displayName).tag(viewType)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 6)

                ScrollView {
                    VStack(spacing: 16) {
                        switch state.selectedView {
                        case .overview:
                            StatOverviewView(state: state)
                        case .glucose:
                            glucoseView
                        case .looping:
                            loopingView
                        case .insulin:
                            insulinView
                        case .meals:
                            mealsView
                        }
                    }
                    .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .navigationBarTitle(NSLocalizedString("Statistics", comment: "Statistics tab title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if state.selectedView != .overview {
                        Button {
                            state.selectedView = .overview
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(NSLocalizedString("Back", comment: ""))
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Close", comment: ""), action: state.hideModal)
                }
            }
        }

        // MARK: - Glucose

        @ViewBuilder var glucoseView: some View {
            // Duration picker
            Picker(
                NSLocalizedString("Duration", comment: "Duration picker label"),
                selection: $state.selectedIntervalForGlucoseStats
            ) {
                ForEach(StatsTimeIntervalWithToday.allCases) { interval in
                    Text(interval.displayName)
                }
            }.pickerStyle(.segmented)

            let filter = state.filterDate(for: state.selectedIntervalForGlucoseStats)

            // Chart type picker
            HStack {
                Text(NSLocalizedString("Chart Type", comment: "Chart type section label"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Picker(
                    NSLocalizedString("Glucose Chart Type", comment: "Glucose chart type picker label"),
                    selection: $state.selectedGlucoseChartType
                ) {
                    Text(GlucoseChartType.percentileByTime.displayName)
                        .tag(GlucoseChartType.percentileByTime)
                    Text(GlucoseChartType.distribution.displayName)
                        .tag(GlucoseChartType.distribution)
                }
                .pickerStyle(.menu)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }.padding(.horizontal)

            let agpData: [AGPSlot] = {
                switch state.selectedIntervalForGlucoseStats {
                case .today: return state.agpToday
                case .day: return state.agpDay
                case .week: return state.agpWeek
                case .month: return state.agpMonth
                case .total: return state.agpTotal
                }
            }()
            let distributionData: [GlucoseDistributionSlot] = {
                switch state.selectedIntervalForGlucoseStats {
                case .today: return state.distributionToday
                case .day: return state.distributionDay
                case .week: return state.distributionWeek
                case .month: return state.distributionMonth
                case .total: return state.distributionTotal
                }
            }()

            if state.selectedGlucoseChartType == .distribution {
                GlucoseDistributionCard(
                    distributionData: distributionData,
                    selectedInterval: state.selectedIntervalForGlucoseStats
                )
            } else {
                GlucoseAGPCard(
                    agpData: agpData,
                    highLimit: state.highLimit,
                    lowLimit: state.lowLimit,
                    units: state.units,
                    selectedInterval: state.selectedIntervalForGlucoseStats
                )
            }
            glucoseOverviewCard(filter: filter)
        }

        private func glucoseOverviewCard(filter: NSDate) -> some View {
            GlucoseOverviewCard(
                filter: filter,
                highLimit: state.highLimit,
                lowLimit: state.lowLimit,
                units: state.units,
                overrideUnit: state.overrideUnit
            )
        }

        private func glucoseScatterCard(filter: NSDate) -> some View {
            GlucoseScatterCard(
                filter: filter,
                highLimit: state.highLimit,
                lowLimit: state.lowLimit,
                units: state.units,
                selectedInterval: state.selectedIntervalForGlucoseStats
            )
        }

        // MARK: - Insulin

        @ViewBuilder var insulinView: some View {
            HStack {
                Text(NSLocalizedString("Chart Type", comment: "Chart type section label"))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Picker(
                    NSLocalizedString("Insulin Chart Type", comment: "Insulin chart type picker label"),
                    selection: $state.selectedInsulinChartType
                ) {
                    ForEach(InsulinChartType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }.padding(.horizontal)

            Picker(
                NSLocalizedString("Duration", comment: "Duration picker label"),
                selection: $state.selectedIntervalForInsulinStats
            ) {
                ForEach(StatsTimeIntervalWithToday.allCases) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }.pickerStyle(.segmented)

            insulinChartCard
            insulinSummaryCard
        }

        @ViewBuilder private var insulinSummaryCard: some View {
            StatCard {
                InsulinStatsTileView(
                    neg: state.neg,
                    tddChange: state.tddChange,
                    tddAverage: state.tddAverage,
                    tddYesterday: state.tddYesterday,
                    tdd2DaysAgo: state.tdd2DaysAgo,
                    tdd3DaysAgo: state.tdd3DaysAgo,
                    tddActualAverage: state.tddActualAverage
                )
            }
        }

        @ViewBuilder private var insulinChartCard: some View {
            StatCard {
                switch state.selectedInsulinChartType {
                case .totalDailyDose:
                    let tddData: [TDDStats] = {
                        switch state.selectedIntervalForInsulinStats {
                        case .today: return state.hourlyTDDStats
                        case .day: return state.last24hHourlyTDDStats
                        default: return state.filteredDailyTDDStats
                        }
                    }()
                    if tddData.isEmpty {
                        ContentUnavailableView(
                            NSLocalizedString("No TDD Data", comment: ""),
                            systemImage: "chart.bar.xaxis",
                            description: Text(NSLocalizedString(
                                "Total Daily Doses will appear here once data is available.",
                                comment: "Empty state for TDD chart"
                            ))
                        )
                    } else {
                        TotalDailyDoseChart(
                            selectedInterval: $state.selectedIntervalForInsulinStats,
                            tddStats: tddData
                        )
                    }

                case .bolusDistribution:
                    let bolusData: [BolusStats] = {
                        switch state.selectedIntervalForInsulinStats {
                        case .today: return state.hourlyBolusStats
                        case .day: return state.last24hHourlyBolusStats
                        default: return state.filteredDailyBolusStats
                        }
                    }()
                    let hasData = bolusData.contains { $0.manualBolus > 0 || $0.external > 0 }
                    if bolusData.isEmpty || !hasData {
                        ContentUnavailableView(
                            NSLocalizedString("No Bolus Data", comment: ""),
                            systemImage: "cross.vial",
                            description: Text(NSLocalizedString(
                                "Bolus statistics will appear here once data is available.",
                                comment: "Empty state for bolus chart"
                            ))
                        )
                    } else {
                        BolusStatsView(
                            selectedInterval: $state.selectedIntervalForInsulinStats,
                            bolusStats: bolusData
                        )
                    }
                }
            }
        }

        // MARK: - Looping

        @ViewBuilder var loopingView: some View {
            Picker(
                NSLocalizedString("Duration", comment: "Duration picker label"),
                selection: $state.selectedIntervalForLoopStats
            ) {
                ForEach(StatsTimeIntervalWithToday.allCases) { interval in
                    Text(interval.displayName)
                }
            }.pickerStyle(.segmented)

            let filter = state.filterDate(for: state.selectedIntervalForLoopStats)
            LoopingCard(filter: filter, selectedInterval: state.selectedIntervalForLoopStats)
        }

        // MARK: - Meals

        @ViewBuilder var mealsView: some View {
            Picker(
                NSLocalizedString("Duration", comment: "Duration picker label"),
                selection: $state.selectedIntervalForMealStats
            ) {
                ForEach(StatsTimeIntervalWithToday.allCases) { interval in
                    Text(interval.displayName).tag(interval)
                }
            }.pickerStyle(.segmented)

            let mealData = state.selectedIntervalForMealStats.isHourly ?
                (state.selectedIntervalForMealStats == .today ? state.todayHourlyMealStats : state.hourlyMealStats) :
                state.filteredDailyMealStats
            let hasData = mealData.contains { $0.carbs > 0 || $0.fat > 0 || $0.protein > 0 }

            StatCard {
                if mealData.isEmpty || !hasData {
                    ContentUnavailableView(
                        NSLocalizedString("No Meal Data", comment: ""),
                        systemImage: "fork.knife",
                        description: Text(NSLocalizedString(
                            "Meal statistics will appear here once data is available.",
                            comment: "Empty state for meal chart"
                        ))
                    )
                } else {
                    MealStatsView(
                        selectedInterval: $state.selectedIntervalForMealStats,
                        mealStats: mealData
                    )
                }
            }

            // Macro distribution donut card
            if hasData {
                let totalCarbs = mealData.map(\.carbs).reduce(0, +)
                let totalFat = mealData.map(\.fat).reduce(0, +)
                let totalProtein = mealData.map(\.protein).reduce(0, +)
                let hasFatProtein = totalFat > 0 || totalProtein > 0
                if hasFatProtein, (totalCarbs + totalFat + totalProtein) > 0 {
                    let interval = state.selectedIntervalForMealStats
                    let daysCount: Int = {
                        switch interval {
                        case .day,
                             .today: return 1
                        case .week: return 7
                        case .month: return 30
                        case .total: return 90
                        }
                    }()
                    StatCard {
                        MacroDistributionDonut(
                            carbs: totalCarbs,
                            fat: totalFat,
                            protein: totalProtein,
                            daysCount: daysCount,
                            showAverage: !interval.isHourly
                        )
                    }
                }
            }
        }
    }
}

// MARK: - StatCard Container

struct StatCard<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .elegantShadow(scheme: colorScheme)
    }
}

// MARK: - Glucose Overview Card (Donut + Metrics)

private struct GlucoseOverviewCard: View {
    @FetchRequest var fetchRequest: FetchedResults<Readings>

    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let overrideUnit: Bool

    init(filter: NSDate, highLimit: Decimal, lowLimit: Decimal, units: GlucoseUnits, overrideUnit: Bool) {
        _fetchRequest = FetchRequest<Readings>(
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "glucose > 0 AND date > %@", filter)
        )
        self.highLimit = highLimit
        self.lowLimit = lowLimit
        self.units = units
        self.overrideUnit = overrideUnit
    }

    var body: some View {
        if fetchRequest.isEmpty {
            StatCard {
                ContentUnavailableView(
                    NSLocalizedString("No Glucose Data", comment: ""),
                    systemImage: "chart.bar.fill",
                    description: Text(NSLocalizedString(
                        "Glucose statistics will appear here once data is available.",
                        comment: "Empty state for glucose chart"
                    ))
                )
            }
        } else {
            StatCard {
                VStack(spacing: 16) {
                    GlucoseSectorChart(
                        highLimit: highLimit,
                        lowLimit: lowLimit,
                        units: units,
                        glucose: fetchRequest,
                        showChart: true
                    )

                    Divider()

                    GlucoseMetricsView(
                        units: units,
                        overrideUnit: overrideUnit,
                        glucose: fetchRequest
                    )
                }
            }

            // Hint
            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                Text(NSLocalizedString(
                    "Tap and hold the ring chart to reveal more details.",
                    comment: "Hint for glucose ring chart"
                ))
                    .foregroundStyle(.secondary)
            }.font(.footnote)
        }
    }
}

// MARK: - Glucose Scatter Card

private struct GlucoseScatterCard: View {
    @FetchRequest var fetchRequest: FetchedResults<Readings>

    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    let selectedInterval: StatsTimeIntervalWithToday

    private let conversionFactor = 0.0555

    init(
        filter: NSDate,
        highLimit: Decimal,
        lowLimit: Decimal,
        units: GlucoseUnits,
        selectedInterval: StatsTimeIntervalWithToday = .today
    ) {
        _fetchRequest = FetchRequest<Readings>(
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate(format: "glucose > 0 AND date > %@", filter)
        )
        self.highLimit = highLimit
        self.lowLimit = lowLimit
        self.units = units
        self.selectedInterval = selectedInterval
    }

    private var xAxisFormat: Date.FormatStyle {
        switch selectedInterval {
        case .day,
             .today: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day().month(.abbreviated)
        case .total: return .dateTime.day().month(.abbreviated)
        }
    }

    var body: some View {
        let low = lowLimit * (units == .mmolL ? Decimal(conversionFactor) : 1)
        let high = highLimit * (units == .mmolL ? Decimal(conversionFactor) : 1)
        let readings = fetchRequest
        let count = readings.count
        let sizeOfDataPoints: CGFloat = count < 20 ? 50 : count < 50 ? 35 : count > 2000 ? 5 : 15

        // Fixed threshold values (180 mg/dL and 70 mg/dL) converted to display units
        let highThreshold: Double = units == .mmolL ? 180 * conversionFactor : 180
        let lowThreshold: Double = units == .mmolL ? 70 * conversionFactor : 70

        StatCard {
            VStack(spacing: 12) {
                Chart {
                    // Fixed threshold lines
                    RuleMark(y: .value("High Threshold", highThreshold))
                        .foregroundStyle(.yellow)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    RuleMark(y: .value("Low Threshold", lowThreshold))
                        .foregroundStyle(.red)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    ForEach(readings.filter({ $0.glucose > Int(highLimit) }), id: \.date) { item in
                        PointMark(
                            x: .value("Date", item.date ?? Date()),
                            y: .value("High", Double(item.glucose) * (units == .mmolL ? conversionFactor : 1))
                        )
                        .foregroundStyle(.orange)
                        .symbolSize(sizeOfDataPoints)
                    }
                    ForEach(
                        readings.filter({ $0.glucose >= Int(lowLimit) && $0.glucose <= Int(highLimit) }),
                        id: \.date
                    ) { item in
                        PointMark(
                            x: .value("Date", item.date ?? Date()),
                            y: .value("In Range", Double(item.glucose) * (units == .mmolL ? conversionFactor : 1))
                        )
                        .foregroundStyle(.green)
                        .symbolSize(sizeOfDataPoints)
                    }
                    ForEach(readings.filter({ $0.glucose < Int(lowLimit) }), id: \.date) { item in
                        PointMark(
                            x: .value("Date", item.date ?? Date()),
                            y: .value("Low", Double(item.glucose) * (units == .mmolL ? conversionFactor : 1))
                        )
                        .foregroundStyle(.red)
                        .symbolSize(sizeOfDataPoints)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel(format: xAxisFormat)
                        AxisGridLine()
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, low, high, units == .mmolL ? 15 : 270])
                }
                .if(selectedInterval == .total) { chart in
                    chart
                        .chartScrollableAxes(.horizontal)
                        .chartXVisibleDomain(length: 30 * 24 * 3600)
                }
                .frame(height: 200)

                // Legend
                ScatterLegend()

                if selectedInterval == .total {
                    HStack {
                        Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                        Text(NSLocalizedString("Swipe to scroll through time.", comment: "Hint for swipeable chart"))
                            .foregroundStyle(.secondary)
                    }.font(.footnote)
                }
            }
        }
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Scatter Legend

private struct ScatterLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            legendDot(color: .red, label: NSLocalizedString("Low", comment: ""))
            legendDot(color: .green, label: NSLocalizedString("In Range", comment: ""))
            legendDot(color: .orange, label: NSLocalizedString("High", comment: ""))
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// MARK: - AGP (Ambulatory Glucose Profile) Card

struct GlucoseAGPCard: View {
    let agpData: [AGPSlot]
    let highLimit: Decimal
    let lowLimit: Decimal
    let units: GlucoseUnits
    var selectedInterval: StatsTimeIntervalWithToday = .week
    @Environment(\.colorScheme) private var colorScheme

    private let conversionFactor = 0.0555

    var body: some View {
        if agpData.isEmpty || agpData.allSatisfy({ $0.p50 == 0 }) {
            StatCard {
                ContentUnavailableView(
                    NSLocalizedString("No Glucose Data", comment: ""),
                    systemImage: "chart.bar.fill",
                    description: Text(NSLocalizedString(
                        "Glucose statistics will appear here once data is available.",
                        comment: "Empty state for glucose chart"
                    ))
                )
            }
        } else {
            let highThreshold = units == .mmolL ? 180.0 * conversionFactor : 180.0
            let lowThreshold = units == .mmolL ? 70.0 * conversionFactor : 70.0
            let yMax = units == .mmolL ? 15.0 : 270.0

            StatCard {
                VStack(spacing: 12) {
                    let showBands = !selectedInterval.isHourly

                    Text(
                        showBands
                            ? NSLocalizedString("Ambulatory Glucose Profile", comment: "AGP chart title")
                            : NSLocalizedString("Glucose", comment: "Glucose chart title")
                    )
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Chart {
                        agpBands(showBands: showBands)
                        agpMedianLine
                        agpThresholds(high: highThreshold, low: lowThreshold)
                    }
                    .chartForegroundStyleScale([
                        "10-90%": Color.blue.opacity(0.3),
                        "25-75%": Color.blue.opacity(0.5),
                        "Median": Color.blue
                    ])
                    .chartLegend(.hidden)
                    .if(selectedInterval == .today) {
                        $0
                            .chartXScale(
                                domain: Calendar.current.startOfDay(for: Date()) ... Calendar.current
                                    .startOfDay(for: Date()).addingTimeInterval(86400)
                            )
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            if let date = value.as(Date.self) {
                                AxisValueLabel {
                                    Text(String(format: "%02d", Calendar.current.component(.hour, from: date)))
                                }
                            }
                            AxisGridLine()
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [0, lowThreshold, highThreshold, yMax])
                    }
                    .frame(height: 140)

                    // Legend
                    HStack(spacing: 14) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.blue)
                                .frame(width: 14, height: 2.5)
                            Text(showBands ? "Median" : NSLocalizedString("Glucose (Median/h)", comment: ""))
                        }
                        if showBands {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(width: 14, height: 10)
                                Text("25–75%")
                            }
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 14, height: 10)
                                Text("10–90%")
                            }
                        }
                    }
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Chart Content Helpers

    @ChartContentBuilder private func agpBands(showBands: Bool) -> some ChartContent {
        if showBands {
            ForEach(agpData) { slot in
                AreaMark(
                    x: .value("Time", slot.date),
                    yStart: .value("P10", slot.p10),
                    yEnd: .value("P90", slot.p90),
                    series: .value("Band", "10-90")
                )
                .foregroundStyle(by: .value("Series", "10-90%"))
                .opacity(slot.p50 > 0 ? 0.3 : 0)
            }

            ForEach(agpData) { slot in
                AreaMark(
                    x: .value("Time", slot.date),
                    yStart: .value("P25", slot.p25),
                    yEnd: .value("P75", slot.p75),
                    series: .value("Band", "25-75")
                )
                .foregroundStyle(by: .value("Series", "25-75%"))
                .opacity(slot.p50 > 0 ? 0.5 : 0)
            }
        }
    }

    @ChartContentBuilder private var agpMedianLine: some ChartContent {
        ForEach(agpData) { slot in
            if slot.p50 > 0 {
                LineMark(
                    x: .value("Time", slot.date),
                    y: .value("Median", slot.p50),
                    series: .value("Line", "Median")
                )
                .foregroundStyle(by: .value("Series", "Median"))
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
    }

    @ChartContentBuilder private func agpThresholds(high: Double, low: Double) -> some ChartContent {
        RuleMark(y: .value("High", high))
            .foregroundStyle(Color.loopYellow)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        RuleMark(y: .value("Low", low))
            .foregroundStyle(Color.loopRed)
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
}

// MARK: - Glucose Distribution Card

struct GlucoseDistributionCard: View {
    let distributionData: [GlucoseDistributionSlot]
    let selectedInterval: StatsTimeIntervalWithToday
    @Environment(\.colorScheme) private var colorScheme

    private let rangeColors: [(label: String, color: Color)] = [
        (NSLocalizedString("Very High", comment: ""), Color.loopYellow),
        (NSLocalizedString("High", comment: ""), Color.loopYellow.opacity(0.6)),
        (NSLocalizedString("In Range", comment: ""), Color.loopGreen),
        (NSLocalizedString("Low", comment: ""), Color.loopRed.opacity(0.7)),
        (NSLocalizedString("Very Low", comment: ""), Color.loopRed)
    ]

    private var isHourly: Bool { selectedInterval.isHourly }

    private var barUnit: Calendar.Component { isHourly ? .hour : .day }

    var body: some View {
        if distributionData.isEmpty || distributionData.allSatisfy({ $0.inRange == 0 && $0.high == 0 && $0.low == 0 }) {
            StatCard {
                ContentUnavailableView(
                    NSLocalizedString("No Glucose Data", comment: ""),
                    systemImage: "chart.bar.fill",
                    description: Text(NSLocalizedString(
                        "Glucose statistics will appear here once data is available.",
                        comment: "Empty state for glucose chart"
                    ))
                )
            }
        } else {
            StatCard {
                VStack(spacing: 12) {
                    Text(NSLocalizedString("Glucose Distribution", comment: "Distribution chart title"))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Chart {
                        ForEach(distributionData) { slot in
                            BarMark(
                                x: .value("Date", slot.date, unit: barUnit),
                                y: .value("Very Low", slot.veryLow)
                            )
                            .foregroundStyle(Color.loopRed)

                            BarMark(
                                x: .value("Date", slot.date, unit: barUnit),
                                y: .value("Low", slot.low)
                            )
                            .foregroundStyle(Color.loopRed.opacity(0.7))

                            BarMark(
                                x: .value("Date", slot.date, unit: barUnit),
                                y: .value("In Range", slot.inRange)
                            )
                            .foregroundStyle(Color.loopGreen)

                            BarMark(
                                x: .value("Date", slot.date, unit: barUnit),
                                y: .value("High", slot.high)
                            )
                            .foregroundStyle(Color.loopYellow.opacity(0.6))

                            BarMark(
                                x: .value("Date", slot.date, unit: barUnit),
                                y: .value("Very High", slot.veryHigh)
                            )
                            .foregroundStyle(Color.loopYellow)
                        }
                    }
                    .chartXAxis {
                        if isHourly {
                            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                                if let date = value.as(Date.self) {
                                    AxisValueLabel {
                                        Text(String(format: "%02d", Calendar.current.component(.hour, from: date)))
                                    }
                                }
                                AxisGridLine()
                            }
                        } else {
                            AxisMarks(values: .automatic) { _ in
                                AxisValueLabel(
                                    format: selectedInterval == .week
                                        ? .dateTime.weekday(.abbreviated)
                                        : .dateTime.day().month(.abbreviated)
                                )
                                AxisGridLine()
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisValueLabel {
                                if let val = value.as(Int.self) {
                                    Text("\(val)%")
                                        .font(.caption)
                                }
                            }
                            AxisGridLine()
                        }
                    }
                    .chartYScale(domain: 0 ... 100)
                    .chartLegend(.hidden)
                    .if(selectedInterval == .total) { chart in
                        chart
                            .chartScrollableAxes(.horizontal)
                            .chartXVisibleDomain(length: 30 * 24 * 3600)
                    }
                    .frame(height: 140)

                    // Legend
                    HStack(spacing: 10) {
                        ForEach(Array(rangeColors.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(item.color)
                                    .frame(width: 10, height: 10)
                                Text(item.label)
                            }
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
