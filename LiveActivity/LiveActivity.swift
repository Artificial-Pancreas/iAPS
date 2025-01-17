import ActivityKit
import Charts
import SwiftUI
import WidgetKit

private enum Size {
    case minimal
    case compact
    case expanded
}

struct LiveActivity: Widget {
    private let dateFormatter: DateFormatter = {
        var formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private let minuteFormatter: NumberFormatter = {
        var formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    @Environment(\.dynamicTypeSize) private var fontSize

    @ViewBuilder private func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if !context.state.change.isEmpty {
            if !context.isStale {
                Text(context.state.change)
            } else {
                Text("old").foregroundStyle(.secondary)
            }
        } else {
            Text("--")
        }
    }

    private func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        let text = Text("\(dateFormatter.string(from: context.state.loopDate))")
        return text
    }

    private func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>, size: Size) -> (some View, Int) {
        var characters = 0

        let bgText = context.state.bg
        characters += bgText.count

        // narrow mode is for the minimal dynamic island view
        // there is not enough space to show all three arrow there
        // and everything has to be squeezed together to some degree
        // only display the first arrow character and make it red in case there were more characters
        var directionText: String?
        var warnColor: Color?
        if let direction = context.state.direction {
            if size == .compact {
                directionText = String(direction[direction.startIndex ... direction.startIndex])

                if direction.count > 1 {
                    warnColor = Color.red
                }
            } else {
                directionText = direction
            }

            characters += directionText!.count
        }

        let spacing: CGFloat
        switch size {
        case .minimal: spacing = -1
        case .compact: spacing = 0
        case .expanded: spacing = 3
        }

        let stack = HStack(spacing: spacing) {
            Text(bgText)

            if let direction = directionText {
                let text = Text(direction)
                switch size {
                case .minimal:
                    let scaledText = text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading)
                    if let warnColor {
                        scaledText.foregroundStyle(warnColor)
                    } else {
                        scaledText
                    }
                case .compact:
                    text.scaleEffect(x: 0.8, y: 0.8, anchor: .leading).padding(.trailing, -3)

                case .expanded:
                    text.scaleEffect(x: 0.7, y: 0.7, anchor: .center).padding(.trailing, -5)
                }
            }
        }
        .foregroundStyle(context.isStale ? .secondary : Color.primary)

        return (stack, characters)
    }

    private func iob(context: ActivityViewContext<LiveActivityAttributes>, size _: Size) -> some View {
        HStack(spacing: 0) {
            Text(context.state.iob)
            Text(" U")
        }
        .foregroundStyle(.insulin)
    }

    private func cob(context: ActivityViewContext<LiveActivityAttributes>, size _: Size) -> some View {
        HStack(spacing: 0) {
            Text(context.state.cob)
            Text(" g")
        }
        .foregroundStyle(.loopYellow)
    }

    private func loop(context: ActivityViewContext<LiveActivityAttributes>, size: CGFloat) -> some View {
        let timeAgo = abs(context.state.loopDate.timeIntervalSinceNow) / 60
        let color: Color = timeAgo > 8 ? .loopYellow : timeAgo > 12 ? .loopRed : .loopGreen
        return LoopActivity(stroke: color, compact: size == 12).frame(width: size)
    }

    private var emptyText: some View {
        Text(" ").font(.caption).offset(x: 0, y: -5)
    }

    private static let eventualSymbol = "⇢"

    private let dropWidth = CGFloat(80)
    private let dropHeight = CGFloat(80)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            let widget = VStack(spacing: 2) {
                if !context.state.showChart {
                    ZStack {
                        updatedLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    HStack(alignment: .top) {
                        loop(context: context, size: 22)
                            .padding(.top, 6)
                        Spacer()
                        VStack(spacing: 0) {
                            bgAndTrend(context: context, size: .expanded).0.font(.title)
                            if !context.state.showChart {
                                changeLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7))
                                    .offset(x: -12, y: -5)
                            }
                        }
                        Spacer()
                        VStack {
                            iob(context: context, size: .expanded).font(.title)
                            emptyText
                        }
                        Spacer()
                        VStack {
                            cob(context: context, size: .expanded).font(.title)
                            emptyText
                        }
                    }

                    HStack {
                        Spacer()
                        Text(NSLocalizedString("Eventual Glucose", comment: ""))
                        Spacer()
                        Text(context.state.eventual)
                        Text(context.state.mmol ? NSLocalizedString(
                            "mmol/L",
                            comment: "The short unit display string for millimoles of glucose per liter"
                        ) : NSLocalizedString(
                            "mg/dL",
                            comment: "The short unit display string for milligrams of glucose per decilter"
                        )).foregroundStyle(.secondary)
                    }.padding(.top, 10)

                } else {
                    HStack(alignment: .top) {
                        VStack {
                            chartView(for: context.state)
                                .overlay {
                                    HStack(spacing: 4) {
                                        Text(LiveActivity.eventualSymbol)
                                            .font(.system(size: 16))
                                            .opacity(0.7)
                                        Text(context.state.eventual).font(.system(size: 18)).opacity(0.8).fontWidth(.condensed)
                                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 15)
                                }
                        }
                        .padding(.vertical, 15).padding(.leading, 15).padding(.trailing, 10)
                        .background(.black.opacity(0.30))

                        ZStack(alignment: .topTrailing) { // to make timestamp label overlap the image a little bit
                            VStack(alignment: .trailing, spacing: 0) {
                                glucoseDrop(context.state)

                                Grid(horizontalSpacing: 0) {
                                    GridRow {
                                        HStack(spacing: 1) {
                                            Text(context.state.iob)
                                                .font(.system(size: 22))
                                                .foregroundStyle(.insulin)

                                            Text("U")
                                                .font(.system(size: 22).smallCaps())
                                                .foregroundStyle(.insulin)
                                        }
                                        .fontWidth(.condensed)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        HStack(spacing: 1) {
                                            Text(context.state.cob)
                                                .foregroundStyle(.loopYellow)

                                            Text("g")
                                                .foregroundStyle(.loopYellow)
                                        }
                                        .font(.system(size: 22))
                                        .fontWidth(.condensed)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    }
                                }
                                .frame(width: dropWidth)
                            }
                            .padding(.top, 10)

//                            updatedLabel(context: context)
//                                .font(.system(size: 11))
//                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.top, 15)
                        .padding(.bottom, 15)
                        .padding(.trailing, 15)
                    }
                }
            }
            .privacySensitive()
            .padding(0)
            // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
            // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
            // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
            if context.state.showChart {
                widget
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.6))
                    .activityBackgroundTint(Color.clear)
            } else {
                widget
                    .foregroundStyle(Color.primary)
                    .background(BackgroundStyle.background.opacity(0.4))
                    .activityBackgroundTint(Color.clear)
                    .padding(.vertical, 10).padding(.horizontal, 16)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        loop(context: context, size: 23)
                    }.padding(10)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        HStack {
                            iob(context: context, size: .expanded).font(.title2).padding(.leading, 10)
                            Spacer()
                            cob(context: context, size: .expanded).font(.title2).padding(10)
                        }
                        HStack {
                            bgAndTrend(context: context, size: .expanded).0.font(.title2).padding(.leading, 10)
                            Spacer()
                            changeLabel(context: context).font(.title2).padding(10)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                        .padding(.trailing, 10)
                }
                DynamicIslandExpandedRegion(.bottom) {}
            } compactLeading: {
                HStack {
                    loop(context: context, size: 12)
                    bgAndTrend(context: context, size: .compact).0.padding(.leading, 4)
                }
            } compactTrailing: {
                changeLabel(context: context).padding(.trailing, 4)
            } minimal: {
                let (_label, characterCount) = bgAndTrend(context: context, size: .minimal)

                let label = _label.padding(.leading, 7).padding(.trailing, 3)

                if characterCount < 4 {
                    label
                } else if characterCount < 5 {
                    label.fontWidth(.condensed)
                } else {
                    label.fontWidth(.compressed)
                }
            }
            .widgetURL(URL(string: "freeaps-x://"))
            // .keylineTint(Color.purple)
            .contentMargins(.horizontal, 0, for: .minimal)
            .contentMargins(.trailing, 0, for: .compactLeading)
            .contentMargins(.leading, 0, for: .compactTrailing)
        }
    }

    private var decimalString: String {
        let formatter = NumberFormatter()
        return formatter.decimalSeparator
    }

    private func glucoseDrop(_ state: LiveActivityAttributes.ContentState) -> some View {
        ZStack {
            let degree = dropAngle(state)
            let shadowDirection = direction(degree: degree)

            Image("glucoseDrops")
                .resizable()
                .frame(width: dropWidth, height: dropHeight).rotationEffect(.degrees(degree))
                .animation(.bouncy(duration: 1, extraBounce: 0.2), value: degree)
                .shadow(radius: 3, x: shadowDirection.x, y: shadowDirection.y)

            let string = state.bg
            let decimalSeparator =
                string.contains(decimalString) ? decimalString : "."

            let decimal = string.components(separatedBy: decimalSeparator)
            if decimal.count > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(decimal[0]).font(Font.custom("SuggestionSmallPartsFont", size: 25))
                    Text(decimalSeparator).font(.system(size: 18).weight(.semibold)) // .baselineOffset(-10)
                    Text(decimal[1]).font(.system(size: 18)) // .baselineOffset(-10)
                }
                .tracking(-1)
                .offset(x: -2)
                .foregroundColor(colorOfGlucose())
            } else {
                Text(string)
                    .font(Font.custom("SuggestionSmallPartsFont", size: 25).width(.condensed)) // .tracking(-2)
                    .foregroundColor(colorOfGlucose())
            }
        }
        .frame(width: dropWidth, height: dropHeight)
    }

    private func colorOfGlucose() -> Color {
        Color.white
    }

    private func dropAngle(_ state: LiveActivityAttributes.ContentState) -> Double {
        guard let direction = state.direction else {
            return 90
        }

        switch direction {
        case "↑",
             "↑↑",
             "↑↑↑":
            return 0
        case "↗︎":
            return 45
        case "→":
            return 90
        case "↘︎":
            return 135
        case "↓",
             "↓↓",
             "↓↓↓":
            return 180
        default:
            return 90
        }
    }

    private func direction(degree: Double) -> (x: CGFloat, y: CGFloat) {
        switch degree {
        case 0:
            return (0, -2)
        case 45:
            return (1, -2)
        case 90:
            return (2, 0)
        case 135:
            return (1, 2)
        case 180:
            return (0, 2)
        default:
            return (2, 0)
        }
    }

    private func displayValues(_ values: [Int16], mmol: Bool) -> [Double] {
        values.map {
            mmol ?
                Double($0) * 0.0555 :
                Double($0)
        }
    }

    private func createYScale(
        _ state: LiveActivityAttributes.ContentState,
        _ maxValue: Double?,
        _ highThreshold: Int16
    ) -> ClosedRange<Double> {
        let minValue = state.mmol ? 54 * 0.0555 : 54
        let maxThresholdDouble =
            state.mmol ? Double(highThreshold) * 0.0555 : Double(highThreshold)

        let maxDataOrThreshold: Double

        if let maxValue, maxValue > maxThresholdDouble {
            maxDataOrThreshold = maxValue
        } else {
            maxDataOrThreshold = maxThresholdDouble
        }

        return Double(minValue) * 0.9 ... Double(maxDataOrThreshold * 1.1)
    }

    private func makePoints(_ dates: [Date], _ values: [Int16], mmol: Bool) -> [(date: Date, value: Double)] {
        zip(dates, displayValues(values, mmol: mmol)).map { ($0, $1) }
    }

    private func chartView(for state: LiveActivityAttributes.ContentState) -> some View {
        let readings = state.readings ?? LiveActivityAttributes.ValueSeries(dates: [], values: [])
        let dates = readings.dates
        let displayedValues = makePoints(dates, readings.values, mmol: state.mmol)

        var minValue = displayedValues.min { $0.value < $1.value }?.value
        var maxValue = displayedValues.max { $0.value < $1.value }?.value
        let minYMark = minValue
        let maxYMark = maxValue
        let haveReadings = minValue != nil && maxValue != nil

        let glucoseFormatter: FloatingPointFormatStyle<Double> =
            state.mmol ?
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")) :
            .number.precision(.fractionLength(0))

        func updateMinMax(_ values: [(date: Date, value: Double)]) -> [(date: Date, value: Double)] {
            let minHere = values.min { $0.value < $1.value }?.value ?? Double(0)
            let maxHere = values.max { $0.value < $1.value }?.value ?? Double(0)
            if let currMinValue = minValue, minHere < currMinValue { minValue = minHere }
            if let currMaxValue = maxValue, maxHere > currMaxValue { maxValue = maxHere }
            return values
        }

        let readingsSymbolSize = CGFloat(15)

        let predictionsOpacity = 0.3
        let predictionsSymbolSize = CGFloat(10)

        return Chart {
            ForEach(displayedValues, id: \.date) {
                PointMark(
                    x: .value("Time", $0.date),
                    y: .value("Glucose", $0.value)
                )
                .symbolSize(readingsSymbolSize)
                .foregroundStyle(.darkGreen)
                LineMark(
                    x: .value("Time", $0.date),
                    y: .value("Glucose", $0.value)
                )
                .foregroundStyle(.darkGreen)
                .opacity(0.7)
                .lineStyle(StrokeStyle(lineWidth: 1.0))
            }

            if haveReadings, let iob = state.predictions?.iob.map({
                updateMinMax(makePoints($0.dates, $0.values, mmol: state.mmol))
            }) {
                ForEach(iob, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("IOB", point.value)
                    )
                    .symbolSize(predictionsSymbolSize)
                    .opacity(predictionsOpacity)
                    .foregroundStyle(Color.insulin)
                }
            }
            if haveReadings, let zt = state.predictions?.zt.map({
                updateMinMax(makePoints($0.dates, $0.values, mmol: state.mmol))
            }) {
                ForEach(zt, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("ZT", point.value)
                    )
                    .symbolSize(predictionsSymbolSize)
                    .opacity(predictionsOpacity)
                    .foregroundStyle(Color.zt)
                }
            }
            if haveReadings, let cob = state.predictions?.cob.map({
                updateMinMax(makePoints($0.dates, $0.values, mmol: state.mmol))
            }) {
                ForEach(cob, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("COB", point.value)
                    )
                    .symbolSize(predictionsSymbolSize)
                    .opacity(predictionsOpacity)
                    .foregroundStyle(Color.loopYellow)
                }
            }
            if haveReadings, let uam = state.predictions?.uam.map({
                updateMinMax(makePoints($0.dates, $0.values, mmol: state.mmol))
            }) {
                ForEach(uam, id: \.date) { point in
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("UAM", point.value)
                    )
                    .symbolSize(predictionsSymbolSize)
                    .opacity(predictionsOpacity)
                    .foregroundStyle(Color.uam)
                }
            }

            if let xStart = dates.min(),
               let xEnd = [
                   state.predictions?.iob?.dates.last,
                   state.predictions?.cob?.dates.last,
                   state.predictions?.zt?.dates.last,
                   state.predictions?.uam?.dates.last,
                   displayedValues.last?.date
               ].compactMap({ $0 }).max()
            {
                let yStart = state.mmol ? Double(state.chartLowThreshold) * 0.0555 : Double(state.chartLowThreshold)
                let yEnd = state.mmol ? Double(state.chartHighThreshold) * 0.0555 : Double(state.chartHighThreshold)

                RectangleMark(
                    xStart: .value("Start", xStart),
                    xEnd: .value("End", xEnd),
                    yStart: .value("Bottom", yStart),
                    yEnd: .value("Top", yEnd)
                )
                .foregroundStyle(.green.opacity(0.2))
            }

//                RuleMark(y: .value(
//                    "Low Threshold",
//                    state.mmol ? Double(state.chartLowThreshold) * 0.0555 : Double(state.chartLowThreshold)
//                ))
//                .foregroundStyle(.red.opacity(0.4))
//                .lineStyle(StrokeStyle(lineWidth: 2, dash: [1, 1]))
//
//                RuleMark(y: .value(
//                    "High Threshold",
//                    state.mmol ? Double(state.chartHighThreshold) * 0.0555 : Double(state.chartHighThreshold)
//                ))
//                .foregroundStyle(.orange.opacity(0.4))
//                .lineStyle(StrokeStyle(lineWidth: 2, dash: [1, 1]))

//                    RuleMark(x: .value("Now", Date.now))
//                        .foregroundStyle(.white.opacity(0.4))
//                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .chartYScale(
            domain:
            (state.mmol ? 54 * 0.0555 : 54) ... (state.mmol ? 400 * 0.0555 : 400)
//                            createYScale(state, maxValue, state.chartHighThreshold)
        )
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.2))
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(.secondary)
            }
            AxisMarks(
                position: .top,
                values: [state.loopDate]
            ) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.7))
                AxisValueLabel(format: .dateTime.hour().minute(), anchor: .top)
                    .foregroundStyle(.secondary)
                    .offset(y: -20)
            }
        }
        .chartYAxis {
            if let minYMark, let maxYMark {
                AxisMarks(
                    position: .leading,
                    values:
                    abs(maxYMark - minYMark) < 0.8 ? [
                        (maxYMark + minYMark) / 2
                    ] :
                        [
                            minYMark,
                            maxYMark
                        ]
                ) { _ in
//                        AxisGridLine().foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel(
                        format: glucoseFormatter,
                        horizontalSpacing: 10
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension LiveActivityAttributes {
    static var preview: LiveActivityAttributes {
        LiveActivityAttributes(startDate: Date())
    }
}

private extension LiveActivityAttributes.ContentState {
    // 0 is the widest digit. Use this to get an upper bound on text width.

    // Use mmol/l notation with decimal point as well for the same reason, it uses up to 4 characters, while mg/dl uses up to 3
    static var testWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "→",
            change: "+0.1",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: nil,
            predictions: nil,
            showChart: false,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var testVeryWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "↑↑",
            change: "+1.4",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: nil,
            predictions: nil,
            showChart: false,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var testSuperWide: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "↑↑↑",
            change: "+2.1",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: nil,
            predictions: nil,
            showChart: false,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    // 2 characters for BG, 1 character for change is the minimum that will be shown
    static var testNarrow: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "↑",
            change: "+0.7",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: nil,
            predictions: nil,
            showChart: false,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var testMedium: LiveActivityAttributes.ContentState {
        LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "↗︎",
            change: "+0.8",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: nil,
            predictions: nil,
            showChart: false,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var chart1: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "→",
            change: "+0.1",
            date: Date(),
            iob: "-0.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var chart2: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "13.7",
            direction: "↑↑",
            change: "+1.4",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: nil,
            showChart: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var chart3: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "71",
            direction: "↓↓",
            change: "-1.4",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: nil,
            showChart: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var chart4: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "↗︎",
            change: "+0.1",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }

    static var chart5: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "10.7",
            direction: "↘︎",
            change: "+0.1",
            date: Date(),
            iob: "11.2",
            cob: "120",
            loopDate: Date.now, eventual: "12.7", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200
        )
    }
}

struct SampleData {
    let sampleReadings: LiveActivityAttributes.ValueSeries
    let samplePredictions: LiveActivityAttributes.ActivityPredictions

    init() {
        let calendar = Calendar.current
        let now = Date.now

        let readingDates = Array((0 ..< 2 * 12).map { minutesAgoX5 in
            calendar.date(byAdding: .minute, value: -minutesAgoX5 * 5, to: now)!
        }.reversed())

        var current = 100 + Int.random(in: 0 ... 100)
        let readingValues: [Int16] = Array((0 ..< 2 * 12).map { _ in
            current = current + Int.random(in: 10 ... 20) * Int.random(in: -50 ... 50).signum()
//            current = 100 + Int.random(in: 0 ... 5) * Int.random(in: -50 ... 50).signum()
            if current < 100 {
                current = 100 + Int.random(in: 0 ... 10)
            }
            return Int16(clamping: current)
        }.reversed())

        sampleReadings = LiveActivityAttributes.ValueSeries(
            dates: readingDates,
            values: readingValues
        )

        let lastGlucose = Double(readingValues.last!)
        let lastDate = readingDates.last!

        let numberOfPoints = 2 * 60 / 5 // 2 hours with 5-minute steps

        // Helper function to generate a curve with some randomness
        func generateCurve(startValue: Double, pattern: String) -> LiveActivityAttributes.ValueSeries {
            var values: [Double] = []
            var currentValue = startValue

            let midpoint = Double(numberOfPoints) / 2

            for i in 0 ..< numberOfPoints {
                let noise = Double.random(in: -5 ... 5)
                switch pattern {
                case "up":
                    currentValue += Double.random(in: 5 ... 15) + noise
                    if currentValue > 400 {
                        currentValue = 400 - Double.random(in: 0 ... 15)
                    }
                case "down":
                    currentValue -= Double.random(in: 5 ... 15) + noise
                    if currentValue < 20 {
                        currentValue = 20 + Double.random(in: 0 ... 15)
                    }
                case "peak":
                    let distance = abs(Double(i) - midpoint)
                    let trend = distance < midpoint / 2 || currentValue > 300 ? -1.0 : 1.0
                    let delta = Double.random(in: 5 ... 20)
                    currentValue += delta * trend + noise
                default:
                    currentValue += noise
                }
                values.append(currentValue)
            }

            let dates = values.enumerated().map { index, _ in
                lastDate.addingTimeInterval(TimeInterval((index + 1) * 5 * 60))
            }

            return LiveActivityAttributes.ValueSeries(dates: dates, values: values.map {
                Int16(clamping: Int(round($0)))
            })
        }

        let iob = generateCurve(startValue: lastGlucose, pattern: "down")
        let zt = generateCurve(startValue: lastGlucose, pattern: "stable")
        let cob = generateCurve(startValue: lastGlucose, pattern: "peak")
        let uam = generateCurve(startValue: lastGlucose, pattern: "up")

        samplePredictions = LiveActivityAttributes.ActivityPredictions(
            iob: iob,
            zt: zt,
            cob: cob,
            uam: uam
        )
    }
}

extension Color {
    static let uam = Color("UAM")
    static let zt = Color("ZT")
}

@available(iOS 17.0, iOSApplicationExtension 17.0, *)
#Preview("Notification", as: .content, using: LiveActivityAttributes.preview) {
    LiveActivity()
} contentStates: {
    LiveActivityAttributes.ContentState.testSuperWide
    LiveActivityAttributes.ContentState.testVeryWide
    LiveActivityAttributes.ContentState.testWide
    LiveActivityAttributes.ContentState.testMedium
    LiveActivityAttributes.ContentState.testNarrow
    LiveActivityAttributes.ContentState.chart1
    LiveActivityAttributes.ContentState.chart2
    LiveActivityAttributes.ContentState.chart3
    LiveActivityAttributes.ContentState.chart4
    LiveActivityAttributes.ContentState.chart5
}

struct LoopActivity: View {
    @Environment(\.colorScheme) var colorScheme
    let stroke: Color
    let compact: Bool
    var body: some View {
        Circle()
            .stroke(stroke, lineWidth: compact ? 1.5 : 3)
    }
}
