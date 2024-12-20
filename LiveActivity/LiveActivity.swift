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
    
    private func displayValues(_ readings: [LiveActivityAttributes.ContentStateReading], mmol: Bool) -> [(date: Date, mgdl: Int16, value: Double)] {
        readings.map { reading in
            (
                date: reading.date,
                mgdl: reading.glucose,
                value: mmol ?
                    Double(reading.glucose) * 0.0555 :
                    Double(reading.glucose)
            )
        }
    }
    
    private func createYScale(
        _ state: LiveActivityAttributes.ContentState,
        _ maxValue: Double
    ) -> ClosedRange<Double> {
        let minValue = state.mmol ? 36 * 0.0555 : 36
        
        if let settingsMaxValue = state.chartMaxValue {
            let settingsMaxDouble = Double(settingsMaxValue)
            let settingsMaxDoubleConverted = state.mmol ? settingsMaxDouble * 0.0555 : settingsMaxDouble
           
            if settingsMaxDoubleConverted > maxValue {
                return Double(minValue)...Double(settingsMaxDoubleConverted)
            } else {
                return Double(minValue)...Double(maxValue)
            }
        } else {
            return Double(minValue)...Double(maxValue)
        }
        
    }
    
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack(spacing: 2) {
                ZStack {
                    updatedLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                HStack {
                    VStack {
                        loop(context: context, size: 22)
                        emptyText
                    }.offset(x: 0, y: 2)
                    Spacer()
                    VStack {
                        bgAndTrend(context: context, size: .expanded).0.font(.title)
                        changeLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7)).offset(x: -12, y: -5)
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

                if context.state.showChart {
                    chartView(for: context.state)
                }
                HStack {
                    Spacer()
                    if context.state.eventualText {
                        Text(NSLocalizedString("Eventual Glucose", comment: ""))
                        Spacer()
                    } else {
                        Text("⇢").foregroundStyle(.secondary).font(.system(size: UIFont.systemFontSize * 1.8))
                    }
                    Text(context.state.eventual)
                    Text(context.state.mmol ? NSLocalizedString(
                        "mmol/L",
                        comment: "The short unit display string for millimoles of glucose per liter"
                    ) : NSLocalizedString(
                        "mg/dL",
                        comment: "The short unit display string for milligrams of glucose per decilter"
                    )).foregroundStyle(.secondary)
                }.padding(.top, context.state.showChart ? 0 : 10)
            }
            .privacySensitive()
            .padding(.vertical, 10).padding(.horizontal, 15)
            // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
            // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
            // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
            .foregroundStyle(Color.primary)
            .background(BackgroundStyle.background.opacity(0.4))
            .activityBackgroundTint(Color.clear)
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
    private func chartView(for state: LiveActivityAttributes.ContentState) -> some View {
        let displayedValues = displayValues(state.readings, mmol: state.mmol)

        let minValue = displayedValues.min { $0.value < $1.value }?.value ?? Double(0)
        let maxValue = displayedValues.max { $0.value < $1.value }?.value ?? Double(0)
        
        return Chart {
            ForEach(displayedValues, id: \.date) {
                PointMark(
                    x: .value("Time", $0.date),
                    y: .value("Glucose", $0.value)
                )
                .symbolSize(20)
                .foregroundStyle(.darkGreen)
                LineMark(
                    x: .value("Time", $0.date),
                    y: .value("Glucose", $0.value)
                )
                .foregroundStyle(.darkGreen)
            }
            
            if state.showPredictions {
                
                let iobValues =
                    state.predictions?.iob.map({
                        displayValues($0, mmol: state.mmol)
                    })
                
                let ztValues =
                    state.predictions?.zt.map({
                        displayValues($0, mmol: state.mmol)
                    })
                
                let cobValues =
                    state.predictions?.cob.map({
                        displayValues($0, mmol: state.mmol)
                    })
                
                let uamValues =
                    state.predictions?.uam.map({
                        displayValues($0, mmol: state.mmol)
                    })
                
                if let iob = iobValues {
                    ForEach(iob, id: \.date) { point in
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.value)
                        )
                        .symbolSize(5)
                        .foregroundStyle(Color.insulin.opacity(0.7))
                    }
                }
                if let zt = ztValues {
                    ForEach(zt, id: \.date) { point in
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.value)
                        )
                        .symbolSize(5)
                        .foregroundStyle(Color.zt.opacity(0.7))
                    }
                }
                if let cob = cobValues {
                    ForEach(cob, id: \.date) { point in
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.value)
                        )
                        .symbolSize(5)
                        .foregroundStyle(Color.loopYellow.opacity(0.7))
                    }
                }
                if let uam = uamValues {
                    ForEach(uam, id: \.date) { point in
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Glucose", point.value)
                        )
                        .symbolSize(5)
                        .foregroundStyle(Color.uam.opacity(0.7))
                    }
                }
                
                
            }
            
            
            if let chartHighThreshold = state.chartHighThreshold {
                RuleMark(y: .value("High Threshold", state.mmol ? Double(chartHighThreshold) * 0.0555 : Double(chartHighThreshold)))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            if let chartLowThreshold = state.chartLowThreshold {
                RuleMark(y: .value("Low Threshold", state.mmol ? Double(chartLowThreshold) * 0.0555 : Double(chartLowThreshold)))
                    .foregroundStyle(.orange.opacity(0.6))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
            }
            
            
        }
        .chartYScale(domain: createYScale(state, maxValue))
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [
                minValue,
                maxValue
            ]) { _ in
                AxisGridLine()
                AxisValueLabel(
                    format: state.mmol ?
                        .number.precision(.fractionLength(1)) :  // 1 decimal place for mmol
                        .number.precision(.fractionLength(0))
                )
                .foregroundStyle(.secondary)
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
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "00.0",
            direction: "→",
            change: "+0.0",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "100", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            showPredictions: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200,
            chartMaxValue: 400,
            eventualText: false
        )
    }

    static var testVeryWide: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "00.0",
            direction: "↑↑",
            change: "+0.0",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "100", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            showPredictions: false,
            chartLowThreshold: nil,
            chartHighThreshold: nil,
            chartMaxValue: 400,
            eventualText: true
        )
    }

    static var testSuperWide: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "00.0",
            direction: "↑↑↑",
            change: "+0.0",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "100", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            showPredictions: true,
            chartLowThreshold: 75,
            chartHighThreshold: 200,
            chartMaxValue: nil,
            eventualText: false
        )
    }

    // 2 characters for BG, 1 character for change is the minimum that will be shown
    static var testNarrow: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "00",
            direction: "↑",
            change: "+0",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "100", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: false,
            showPredictions: false,
            chartLowThreshold: nil,
            chartHighThreshold: nil,
            chartMaxValue: nil,
            eventualText: true
        )
    }

    static var testMedium: LiveActivityAttributes.ContentState {
        let sampleData = SampleData()
        return LiveActivityAttributes.ContentState(
            bg: "000",
            direction: "↗︎",
            change: "+00",
            date: Date(),
            iob: "1.2",
            cob: "20",
            loopDate: Date.now, eventual: "100", mmol: true,
            readings: sampleData.sampleReadings,
            predictions: sampleData.samplePredictions,
            showChart: true,
            showPredictions: false,
            chartLowThreshold: nil,
            chartHighThreshold: nil,
            chartMaxValue: nil,
            eventualText: true
        )
    }
}

struct SampleData {
    
    let sampleReadings: [LiveActivityAttributes.ContentStateReading] = {
        let calendar = Calendar.current
        let now = Date()

        return (0 ..< 2 * 12).map { minutesAgoX5 in
            let date = calendar.date(byAdding: .minute, value: -minutesAgoX5*5, to: now)!
            let glucose = Int16(70 + arc4random_uniform(200))

            return LiveActivityAttributes.ContentStateReading(
                date: date,
                glucose: glucose
            )
        }.reversed()
    }()
    
    var samplePredictions: LiveActivityAttributes.ActivityPredictions {
        let lastReading = sampleReadings.last!
        
        let lastGlucose = Double(lastReading.glucose)
        let lastDate = lastReading.date
        
        let numberOfPoints = 2 * 60 / 5 // 2 hours with 5-minute steps
//        let numberOfPoints = 30 / 5 // 2 hours with 5-minute steps
        
        // Helper function to generate a curve with some randomness
        func generateCurve(startValue: Double, pattern: String) -> [LiveActivityAttributes.ContentStateReading] {
            var values: [Double] = []
            var currentValue = startValue
            
            let midpoint = Double(numberOfPoints) / 2
            
            for i in 0..<numberOfPoints {
                let noise = Double.random(in: -1...1)
                switch pattern {
                    case "up":
                        currentValue += Double.random(in: 3...10) + noise
                    case "down":
                        currentValue -= Double.random(in: 3...10) + noise
                    case "peak":
                        let distance = abs(Double(i) - midpoint)
                        let trend = distance < midpoint/2 ? -1 : 1
                        currentValue += Double.random(in: 15...25)*Double(trend) + noise
                    default:
                        currentValue += Double.random(in: -3...3)
                }
                values.append(currentValue)
            }
            
            return values.enumerated().map { index, value in
                let pointDate = lastDate.addingTimeInterval(TimeInterval((index + 1) * 5 * 60))
                return LiveActivityAttributes.ContentStateReading(
                    date: pointDate,
                    glucose: Int16(clamping: Int(value))
                )
            }
        }
        
        let iob = generateCurve(startValue: lastGlucose, pattern: "down")
        let zt = generateCurve(startValue: lastGlucose, pattern: "stable")
        let cob = generateCurve(startValue: lastGlucose, pattern: "peak")
        let uam = generateCurve(startValue: lastGlucose, pattern: "up")
        
        return LiveActivityAttributes.ActivityPredictions(
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
