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

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            if !context.state.showChart {
                bannerWithoutChart(for: context)
            } else {
                bannerWithChart(for: context)
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
                    updatedLabel(context: context).font(.caption)
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

    private func bannerWithChart(for context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        LiveActivityChart(context: context)
    }

    @ViewBuilder private func bannerWithoutChart(for context: ActivityViewContext<LiveActivityAttributes>) -> some View {
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
        }
        .privacySensitive()
        .padding(.vertical, 10).padding(.horizontal, 15)
        // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
        // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
        // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
        .foregroundStyle(Color.primary)
        .background(BackgroundStyle.background.opacity(0.4))
        .activityBackgroundTint(Color.clear)
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

        var current = 120 + Int.random(in: 0 ... 100)
        let readingValues: [Int16] = Array((0 ..< 2 * 12).map { _ in
            current = current + Int.random(in: 10 ... 20) * Int.random(in: -50 ... 50).signum()
            if current < 60 {
                current = 60 + Int.random(in: 0 ... 10)
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
