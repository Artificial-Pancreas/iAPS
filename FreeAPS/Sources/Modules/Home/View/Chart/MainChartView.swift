import Algorithms
import Combine
import SwiftDate
import SwiftUI

enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
}

struct DotInfo {
    let rect: CGRect
    let value: Decimal
    let text: String?
    let textRect: CGRect?
}

struct AnnouncementDot {
    let rect: CGRect
    let value: Decimal
    let note: String
}

struct OverrideStruct {
    let start: Date
    let end: Date
    let glucose: Int
}

typealias GlucoseYRange = (minValue: Int, minY: CGFloat, maxValue: Int, maxY: CGFloat)

struct GlucosePeak {
    let xStart: CGFloat
    let yStart: CGFloat
    let glucose: Int
    let text: String
    let textRect: CGRect
    let type: ExtremumType
}

enum ChartConfig {
    static let endID = "End"
    static let basalHeight: CGFloat = 60
    static let topYPadding: CGFloat = 55
    static let bottomPadding: CGFloat = 20
    static let legendBottomPadding: CGFloat = 8 // without insulin activity: additional legend padding
    static let activityChartHeight: CGFloat = 80
    static let activityChartTopGap: CGFloat = 20 // gap between main chart and activity chart, with legend inside
    static let mainChartBottomPaddingWithActivity: CGFloat = bottomPadding + activityChartHeight + activityChartTopGap
    static let legendBottomPaddingWithActivity: CGFloat = bottomPadding + activityChartHeight
    static let cobChartHeight: CGFloat = activityChartHeight
    static let cobChartTopGap: CGFloat = activityChartTopGap
    static let minAdditionalWidth: CGFloat = 150
    static let maxGlucose = 270
    static let minGlucose = 0 // 45
    static let yLinesCount = 5
    static let glucoseScale: CGFloat = 2 // default 2
    static let bolusSize: CGFloat = 8
    static let bolusScale: CGFloat = 2.5
    static let carbsSize: CGFloat = 6
    static let maxCarbSize: CGFloat = 45
    static let fpuSize: CGFloat = 4
    static let carbsScale: CGFloat = 0.3
    static let fpuScale: CGFloat = 0.5
    static let announcementSize: CGFloat = 8
    static let announcementScale: CGFloat = 2.5
    static let owlSeize: CGFloat = 20
    static let glucoseSize: CGFloat = 4
    static let owlOffset: CGFloat = 100
    static let carbOffset: CGFloat = 13
    static let insulinOffset: CGFloat = 17
    static let pointSizeHeight: Double = 5
    static let pointSizeHeightCarbs: Double = 5
    static let bolusHeight: Decimal = 45
    static let carbHeight: Decimal = 45
    static let carbWidth: CGFloat = 5
    static let peakHorizontalPadding: CGFloat = 4
    static let peakVerticalPadding: CGFloat = 2
    static let peakMargin: CGFloat = 6
    static let peakCornerRadius: CGFloat = 2
    static let insulinCarbLabelMargin: CGFloat = 2
}

struct MainChartView: View {
    @State var data: ChartModel
    @Binding var triggerUpdate: Bool

    @State private var geom: CalculatedGeometries? = nil

    private let calculationQueue = DispatchQueue(label: "MainChartView.calculationQueue")

    @State private var latestSize: CGSize = .zero
    @State private var updatesCancellable: AnyCancellable?

    @State private var sizeChanges = PassthroughSubject<Void, Never>()
    @State private var updateRequests = PassthroughSubject<Void, Never>()
    @Environment(\.scenePhase) private var scenePhase

    @State private var shouldScrollAfterUpdate = true
    @State private var scrollTrigger = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let geom = self.geom {
                    MainChartCanvas(geom: geom, data: data, scrollTrigger: $scrollTrigger)
                }
            }
            .onAppear {
                latestSize = geo.size
                subscribeToUpdates()
                sizeChanges.send(())
            }
            .onChange(of: geo.size) {
                latestSize = geo.size
                sizeChanges.send(())
            }
            .onChange(of: triggerUpdate) {
                updateRequests.send(())
            }
            .onChange(of: data.screenHours) {
                shouldScrollAfterUpdate = true
            }
            .onChange(of: scenePhase) {
                switch scenePhase {
                case .active:
                    shouldScrollAfterUpdate = true
                    subscribeToUpdates()
                    updateRequests.send(())
                case .background,
                     .inactive:
                    unsubscribeFromUpdates()
                }
            }
        }
    }

    private func triggerScroll() {
        scrollTrigger &+= 1
    }

    private func update(fullSize: CGSize) {
        let started = Date.now

        let geom = CalculatedGeometries.make(fullSize: fullSize, data: data)

        // TODO: remove this
        let ended = Date.now
        debug(
            .service,
            "main chart update: \(ended.timeIntervalSince(started) * 1000) milliseconds"
        )

        DispatchQueue.main.async {
            if self.shouldScrollAfterUpdate {
                triggerScroll()
                self.shouldScrollAfterUpdate = false
            }
            self.geom = geom
        }
    }

    private func ping<T: Equatable>(_ p: Published<T>.Publisher) -> AnyPublisher<Void, Never> {
        p.removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private func subscribeToUpdates() {
        guard updatesCancellable == nil else { return }
        let debouncedPublishers: [AnyPublisher<Void, Never>] = [
            ping(data.$screenHours),
            ping(data.$showInsulinActivity),
            ping(data.$showCobChart),
            ping(data.$useInsulinBars),
            ping(data.$useCarbBars),
            ping(data.$tempBasals),
            ping(data.$suspensions),
            ping(data.$maxBasal),
            ping(data.$autotunedBasalProfile),
            ping(data.$glucose),
            ping(data.$activity),
            ping(data.$cob),
            ping(data.$isManual),
            ping(data.$announcement),
            ping(data.$boluses),
            ping(data.$carbs),
            ping(data.$tempTargets),
            ping(data.$suggestion),
            ping(data.$latestOverride),
            ping(data.$overrideHistory),
            ping(data.$lowGlucose),
            ping(data.$highGlucose),
            ping(data.$units),
            ping(data.$minimumSMB),
            ping(data.$chartGlucosePeaks),
            ping(data.$yGridLabels),
            ping(data.$thresholdLines),
            ping(data.$displayYgridLines),
            ping(data.$inRangeAreaFill),
            ping(data.$hidePredictions)
        ]

        let immediatePublishers: [AnyPublisher<Void, Never>] = [
            sizeChanges.eraseToAnyPublisher(),
            updateRequests.eraseToAnyPublisher()
        ]

        let debouncedUpdates: AnyPublisher<Void, Never> =
            Publishers.MergeMany(debouncedPublishers)
                .debounce(for: .milliseconds(15), scheduler: calculationQueue)
                .eraseToAnyPublisher()

        let immediateUpdates: AnyPublisher<Void, Never> =
            Publishers.MergeMany(immediatePublishers)
                .eraseToAnyPublisher()

        updatesCancellable =
            Publishers.MergeMany([debouncedUpdates, immediateUpdates])
                .receive(on: calculationQueue)
                .sink { _ in
                    update(fullSize: latestSize)
                }
    }

    private func unsubscribeFromUpdates() {
        updatesCancellable?.cancel()
        updatesCancellable = nil
    }
}

struct MainChartCanvas: View {
    let geom: CalculatedGeometries
    let data: ChartModel
    @Binding var scrollTrigger: Int

    private enum Command {
        static let open = "🔴"
        static let closed = "🟢"
        static let suspend = "❌"
        static let resume = "✅"
        static let tempbasal = "basal"
        static let bolus = "💧"
        static let meal = "🍴"
        static let override = "👤"
    }

    private let date24Formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("HH")
        return formatter
    }()

    private let glucoseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    var body: some View {
        ZStack {
            yGridView
            mainScrollView
            if data.yGridLabels {
                glucoseLabelsView
            }
            if data.showInsulinActivity, data.insulinActivityLabels {
                activityLabelsView
            }
        }
    }

    var legendPanel: some View {
        ZStack {
            HStack {
                if !data.hidePredictions && data.showPredictionsLegend {
                    Group {
                        Circle().fill(Color.insulin).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("IOB")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.insulin)
                    }
                    Group {
                        Circle().fill(Color.zt).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("ZT")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.zt)
                    }
                    Group {
                        Circle().fill(Color.loopYellow).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("COB")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.loopYellow)
                    }
                    Group {
                        Circle().fill(Color.uam).frame(width: 8, height: 8)
                            .padding(.leading, 8)
                        Text("UAM")
                            .font(.system(size: 12, weight: .bold)).foregroundColor(.uam)
                    }
                }
            }
        }
    }

    private var mainScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { scroll in
                ZStack(alignment: .top) {
                    tempTargetsView.drawingGroup()
                    overridesView.drawingGroup()
                    basalView.drawingGroup()
                    if data.showInsulinActivity || data.showCobChart {
                        legendPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, 20)
                            .padding(
                                .bottom,
                                ChartConfig.bottomPadding + ChartConfig.legendBottomPadding + ChartConfig.activityChartHeight
                            )
                    } else {
                        legendPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, 20)
                            .padding(.bottom, ChartConfig.bottomPadding + ChartConfig.legendBottomPadding)
                    }
                    mainView.id(ChartConfig.endID)
                        .drawingGroup()
                        /* .onChange(of: data.glucose) { _ in
                             scroll.scrollTo(ChartConfig.endID, anchor: .trailing)
                         }
                         .onChange(of: data.suggestion) { _ in
                             scroll.scrollTo(ChartConfig.endID, anchor: .trailing)
                         }
                         .onChange(of: data.tempBasals) { _ in
                             scroll.scrollTo(ChartConfig.endID, anchor: .trailing)
                         } */
                        .onChange(of: scrollTrigger) {
                            DispatchQueue.main.async {
                                scroll.scrollTo(ChartConfig.endID, anchor: .trailing)
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                scroll.scrollTo(ChartConfig.endID, anchor: .trailing)
                            }
                        }
                }
            }
        }
    }

    private var yGridView: some View {
        let useColour = data.displayYgridLines ? Color.secondary : Color.clear
        return ZStack {
            if data.displayYgridLines {
                Path { path in
                    for (line, _) in geom.horizontalGrid {
                        path.move(to: CGPoint(x: 0, y: line))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: line))
                    }
                }.stroke(useColour, lineWidth: 0.15)
            }

            // in-range highlight
            if data.inRangeAreaFill {
                if let (highLineY, _) = geom.highThresholdLine,
                   let (lowLineY, _) = geom.lowThresholdLine
                {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: highLineY))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: highLineY))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: lowLineY))
                        path.addLine(to: CGPoint(x: 0, y: lowLineY))
                        path.addLine(to: CGPoint(x: 0, y: highLineY))
                    }.fill(IAPSconfig.inRangeBackground).opacity(colorScheme == .dark ? 0.15 : 0.20)
                }
            }

            // horizontal limits
            if data.thresholdLines {
                if let (highLineY, _) = geom.highThresholdLine {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: highLineY))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: highLineY))
                    }.stroke(Color.loopYellow, lineWidth: 0.4).opacity(0.8)
                }
                if let (lowLineY, _) = geom.lowThresholdLine {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: lowLineY))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: lowLineY))
                    }.stroke(Color.loopRed, lineWidth: 0.4).opacity(0.8)
                }
            }

            if data.showInsulinActivity || data.showCobChart {
                if data.secondaryChartBackdrop {
                    // background for COB/activity
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geom.fullSize.height - ChartConfig.bottomPadding))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: geom.fullSize.height - ChartConfig.bottomPadding))
                        path
                            .addLine(to: CGPoint(
                                x: geom.fullSize.width,
                                y: geom.fullSize.height - ChartConfig.bottomPadding - ChartConfig.activityChartHeight
                            ))
                        path
                            .addLine(to: CGPoint(
                                x: 0,
                                y: geom.fullSize.height - ChartConfig.bottomPadding - ChartConfig.activityChartHeight
                            ))
                        path.addLine(to: CGPoint(x: 0, y: geom.fullSize.height - ChartConfig.bottomPadding))
                    }.fill(IAPSconfig.activityBackground)
                }
            }

            if data.showInsulinActivity, data.insulinActivityGridLines {
                ForEach([(geom.peakActivity_1unit_y, 1), (geom.peakActivity_maxBolus_y, 2)], id: \.1) { yCoord, _ in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: yCoord))
                        path.addLine(to: CGPoint(x: geom.fullSize.width, y: yCoord))
                    }.stroke(Color.secondary, lineWidth: 0.15)
                }
            }

            // thicker zero guideline for activity/COB
            if data.showInsulinActivity, data.insulinActivityGridLines, let yCoord = geom.activityZeroPointY {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yCoord))
                    path.addLine(to: CGPoint(x: geom.fullSize.width, y: yCoord))
                }.stroke(Color.secondary, lineWidth: 0.4)
            }
        }
    }

    private var glucoseLabelsView: some View {
        ForEach(geom.glucoseLabels, id: \.1) { (lineY, glucose) -> AnyView in
            let value = Double(glucose) *
                (data.units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

            Text(value == 0 ? "" : glucoseFormatter.string(from: value as NSNumber) ?? "")
                .position(CGPoint(x: geom.fullSize.width - 12, y: lineY))
                .font(.bolusDotFont)
                .asAny()
        }
    }

    private var activityLabelsView: some View {
        ForEach(
            [
                (Decimal(1.0), geom.peakActivity_1unit, geom.peakActivity_1unit_y, 1),
                (data.maxBolus, geom.peakActivity_maxBolus, geom.peakActivity_maxBolus_y, 2)
            ],
            id: \.2
        ) { bolus, _, yCoord, _ in
            let value = bolus

            return HStack(spacing: 2) {
                Text(glucoseFormatter.string(from: value as NSNumber) ?? "").font(.bolusDotFont)
                Text("U").font(.bolusDotFont.smallCaps()) // .foregroundStyle(Color.secondary)
            }.foregroundStyle(Color(.insulin).opacity(0.8))
                .position(CGPoint(x: geom.fullSize.width - 12, y: yCoord))
                .asAny()
        }
    }

    private var basalView: some View {
        ZStack {
            geom.tempBasalPath.fill(Color.basal.opacity(0.5))
            geom.tempBasalPath.stroke(Color.insulin, lineWidth: 1)
            geom.regularBasalPath.stroke(Color.insulin, style: StrokeStyle(lineWidth: 0.7, dash: [4]))
            geom.suspensionsPath.stroke(Color.loopGray.opacity(0.7), style: StrokeStyle(lineWidth: 0.7)).scaleEffect(x: 1, y: -1)
            geom.suspensionsPath.fill(Color.loopGray.opacity(0.2)).scaleEffect(x: 1, y: -1)
        }
        .scaleEffect(x: 1, y: -1)
        .frame(
            width: geom.fullGlucoseWidth + geom.additionalWidth
        )
        .frame(maxHeight: ChartConfig.basalHeight)
        .background(Color.clear)
    }

    private var mainView: some View {
        Group {
            VStack {
                ZStack {
                    xGridView
                    bolusView
                    if data.smooth { unSmoothedGlucoseView }
                    else { connectingGlucoseLinesView }
                    glucoseView
                    lowGlucoseView
                    highGlucoseView
                    if data.chartGlucosePeaks {
                        glucosePeaksView
                    }
                    if data.showInsulinActivity {
                        activityView
                    }
                    if data.showCobChart {
                        cobView
                    }
                    carbsView // has to be after activityView()
                    manualGlucoseView
                    manualGlucoseCenterView
                    announcementView
                    if !data.hidePredictions {
                        predictionsView
                    }
                    if data.fpus { fpuView }
                }
                timeLabelsView
            }
        }
        .frame(
            width: geom.fullGlucoseWidth + geom.additionalWidth
        )
    }

    @Environment(\.colorScheme) var colorScheme

    private var xGridView: some View {
        let useColour = data.displayXgridLines ? Color.secondary : Color.clear
        return ZStack {
            Path { path in
                for hour in 0 ..< data.hours + data.hours {
                    if data.screenHours < 12 || hour % 2 == 0 {
                        // only show every second line if screenHours is too big
                        let x = geom.firstHourPosition +
                            geom.oneSecondWidth *
                            CGFloat(hour) * CGFloat(1.hours.timeInterval)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geom.fullSize.height - 20))
                    }
                }
            }
            .stroke(useColour, lineWidth: 0.15)

            Path { path in // vertical timeline
                path.move(to: CGPoint(x: geom.currentTimeX, y: 0))
                path.addLine(to: CGPoint(x: geom.currentTimeX, y: geom.fullSize.height - 20))
            }
            .stroke(
                colorScheme == .dark ? IAPSconfig.chartBackgroundLight : IAPSconfig.chartBackgroundDark,
                style: StrokeStyle(lineWidth: 0.5, dash: [5])
            )
        }
    }

    private var timeLabelsView: some View {
        let format = date24Formatter
        return ZStack {
            ForEach(0 ..< data.hours + data.hours, id: \.hours) { hour in
                if data.screenHours >= 12 && hour % 2 == 1 {
                    // only show every second time label if screenHours is too big
                    EmptyView()
                } else {
                    Text(format.string(from: geom.firstHourDate.addingTimeInterval(hour.hours.timeInterval)))
                        .font(.chartTimeFont)
                        .position(
                            x: geom.firstHourPosition +
                                geom.oneSecondWidth *
                                CGFloat(hour) * CGFloat(1.hours.timeInterval),
                            y: 10.0
                        )
                        .foregroundColor(.secondary)
                }
            }
        }.frame(maxHeight: 20)
    }

    private var lowGlucoseView: some View {
        Path { path in
            for rect in geom.glucoseDots {
                if let glucose = rect.glucose, Decimal(glucose) <= data.lowGlucose {
                    path.addEllipse(in: rect.rect)
                }
            }
        }.fill(Color.red)
    }

    private var glucoseView: some View {
        Path { path in
            for rect in geom.glucoseDots {
                if let glucose = rect.glucose, Decimal(glucose) > data.lowGlucose,
                   Decimal(glucose) < data.highGlucose
                {
                    path.addEllipse(in: rect.rect)
                }
            }
        }.fill(Color(.darkGreen))
    }

    private var highGlucoseView: some View {
        Path { path in
            for rect in geom.glucoseDots {
                if let glucose = rect.glucose, Decimal(glucose) >= data.highGlucose {
                    path.addEllipse(in: rect.rect)
                }
            }
        }.fill(.orange)
    }

    private var glucosePeaksView: some View {
        ForEach(geom.glucosePeaks, id: \.xStart) { peak in
            Group {
                Path { path in
                    path.move(to: CGPoint(x: peak.xStart, y: peak.yStart))
                    path.addLine(to: CGPoint(x: peak.textRect.midX, y: peak.textRect.midY))
                }
                .stroke(Color.secondary, lineWidth: 0.75)
                .opacity(0.75)
                .mask(
                    // the line goes from the center of the bg dot to the center of the text label
                    // because of this mask (which is a "copy" of the actual label below) - the line doesn't go under the label, even though it's semi-transparent
                    // a simpler solution is to fill the rectangle below with 1.0 opacity - but needs a better colour
                    ZStack {
                        Color.white // allow everywhere by default
                        Text(peak.text)
                            .font(geom.peaksFont)
                            .padding(.horizontal, ChartConfig.peakHorizontalPadding)
                            .padding(.vertical, ChartConfig.peakVerticalPadding)
                            .background(
                                RoundedRectangle(cornerRadius: ChartConfig.peakCornerRadius)
                                    .fill(Color.black) // cut out this area
                            )
                            .position(CGPoint(x: peak.textRect.midX, y: peak.textRect.midY))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )

                let glucoseDecimal = Decimal(peak.glucose)
                let fillColour = {
                    if glucoseDecimal < data.lowGlucose {
                        return colorScheme == .dark ? Color.peakRed.opacity(0.7) : Color.peakRed.opacity(0.7)
                    }
                    if glucoseDecimal > data.highGlucose {
                        return colorScheme == .dark ? Color.peakOrange.opacity(0.4) : Color.peakYellow
                            .opacity(0.4)
                    }
                    return colorScheme == .dark ? Color.peakGreen.opacity(0.6) : Color.peakGreen.opacity(0.4)
                }()

                ZStack {
                    Text(peak.text)
                        .font(geom.peaksFont)
                        .padding(.horizontal, ChartConfig.peakHorizontalPadding)
                        .padding(.vertical, ChartConfig.peakVerticalPadding)
                        .background(
                            RoundedRectangle(cornerRadius: ChartConfig.peakCornerRadius)
                                .fill(fillColour)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.primary, lineWidth: 0.5)
                                .opacity(0.9)
                        )
                }
                .position(CGPoint(x: peak.textRect.midX, y: peak.textRect.midY))
            }
            .asAny()
        }
    }

    private var activityView: some View {
        ZStack {
            positiveActivityFillPath()
                .fill(Color.blue.opacity(0.3))

            negativeActivityFillPath()
                .fill(Color.red.opacity(0.3))

            activityStrokePath()
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.5),
                    style: StrokeStyle(lineWidth: 0.5)
                )
        }
    }

    private func positiveActivityFillPath() -> Path {
        Path { path in
            guard geom.activityDots.count >= 2 else { return }
            guard let zeroY = geom.activityZeroPointY else { return }

            var hasPositiveValues = false

            for i in 0 ..< geom.activityDots.count {
                let point = geom.activityDots[i]

                if point.y < zeroY {
                    if !hasPositiveValues {
                        // Start a new positive section
                        path.move(to: CGPoint(x: point.x, y: zeroY))
                        hasPositiveValues = true
                    }
                    path.addLine(to: point)
                } else if hasPositiveValues {
                    // End the positive section
                    path.addLine(to: CGPoint(x: point.x, y: zeroY))
                    path.closeSubpath()
                    hasPositiveValues = false
                }
            }

            // Close final positive section if needed
            if hasPositiveValues {
                let lastPoint = geom.activityDots.last!
                path.addLine(to: CGPoint(x: lastPoint.x, y: zeroY))
                path.closeSubpath()
            }
        }
    }

    private func negativeActivityFillPath() -> Path {
        Path { path in
            guard geom.activityDots.count >= 2 else { return }
            guard let zeroY = geom.activityZeroPointY else { return }

            var hasNegativeValues = false

            for i in 0 ..< geom.activityDots.count {
                let point = geom.activityDots[i]

                if point.y > zeroY {
                    if !hasNegativeValues {
                        // Start a new negative section
                        path.move(to: CGPoint(x: point.x, y: zeroY))
                        hasNegativeValues = true
                    }
                    path.addLine(to: point)
                } else if hasNegativeValues {
                    // End the negative section
                    path.addLine(to: CGPoint(x: point.x, y: zeroY))
                    path.closeSubpath()
                    hasNegativeValues = false
                }
            }

            // Close final negative section if needed
            if hasNegativeValues {
                let lastPoint = geom.activityDots.last!
                path.addLine(to: CGPoint(x: lastPoint.x, y: zeroY))
                path.closeSubpath()
            }
        }
    }

    private func activityStrokePath() -> Path {
        Path { path in
            guard geom.activityDots.count >= 2 else { return }
            path.move(to: geom.activityDots[0])
            for point in geom.activityDots.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private var cobView: some View {
        ZStack {
            cobStrokePath(closed: true)
                .fill(Color.loopYellow.opacity(0.3))
            cobStrokePath(closed: false)
                .stroke(
                    colorScheme == .light ? Color.brown : Color.loopYellow,
                    style: StrokeStyle(lineWidth: 0.5, lineCap: .round)
                )
        }
    }

    private func cobStrokePath(closed: Bool) -> Path {
        Path { path in
            guard let cobZeroPointY = geom.cobZeroPointY else { return }
            var isDrawing = false

            for (point, cob) in geom.cobDots.reversed() {
                if cob.cob > 0 {
                    if !isDrawing {
                        if closed {
                            path.move(to: CGPoint(x: point.x, y: cobZeroPointY))
                            path.addLine(to: point)
                        } else {
                            path.move(to: point)
                        }
                        isDrawing = true
                    } else {
                        path.addLine(to: point)
                    }
                } else {
                    if isDrawing {
                        path.addLine(to: point)
                        isDrawing = false
                    }
                }
            }

            if closed {
                if isDrawing, let (latest, _) = geom.cobDots.first {
                    path.addLine(to: CGPoint(x: latest.x, y: cobZeroPointY))
                }
            }
        }
    }

    private var connectingGlucoseLinesView: some View {
        Path { path in
            var lines: [CGPoint] = []
            for rect in geom.glucoseDots {
                lines.append(CGPoint(x: rect.rect.midX, y: rect.rect.midY))
            }
            path.addLines(lines)
        }
        .stroke(Color.primary, lineWidth: 0.25)
    }

    private var manualGlucoseView: some View {
        Path { path in
            for rect in geom.manualGlucoseDots {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.gray)
    }

    private var announcementView: some View {
        ZStack {
            ForEach(geom.announcementDots, id: \.rect.minX) { info -> AnyView in
                let position = CGPoint(x: info.rect.midX, y: info.rect.maxY - ChartConfig.owlOffset)
                let command = info.note.lowercased()
                let type: String =
                    command.contains("true") ?
                    Command.closed :
                    command.contains("false") ?
                    Command.open :
                    command.contains("suspend") ?
                    Command.suspend :
                    command.contains("resume") ?
                    Command.resume :
                    command.contains("tempbasal") ?
                    Command.tempbasal :
                    command.contains("override") ?
                    Command.override :
                    command.contains("meal") ?
                    Command.meal :
                    command.contains("bolus") ?
                    Command.bolus : ""

                Text(type).font(.announcementSymbolFont).foregroundStyle(.orange)
                    .offset(x: 0, y: -15)
                    .position(position).asAny()
            }
        }
    }

    private var manualGlucoseCenterView: some View {
        Path { path in
            for rect in geom.manualGlucoseDotsCenter {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.red)
    }

    private var unSmoothedGlucoseView: some View {
        Path { path in
            var lines: [CGPoint] = []
            for rect in geom.unSmoothedGlucoseDots {
                lines.append(CGPoint(x: rect.midX, y: rect.midY))
                path.addEllipse(in: rect)
            }
            path.addLines(lines)
        }
        .stroke(Color.secondary, lineWidth: 0.5)
    }

    private var bolusView: some View {
        ZStack {
            let bolusPath = geom.bolusPath
            bolusPath.fill(Color.insulin)
            bolusPath.stroke(Color.primary, lineWidth: 0.3)

            ForEach(geom.bolusDots, id: \.rect.minX) { info in
                if let string = info.text, let textRect = info.textRect {
                    Text(string)
                        .font(geom.bolusFont)
                        .rotationEffect(data.useInsulinBars ? Angle(degrees: -90) : Angle(degrees: 0))
                        .position(
                            CGPoint(x: textRect.midX, y: textRect.midY)
                        )
                }
            }
        }
    }

    private var carbsView: some View {
        ZStack {
            let carbsPath = geom.carbsPath
            carbsPath.fill(Color.loopYellow)
            carbsPath.stroke(Color.primary, lineWidth: 0.3)

            if data.useCarbBars {
                ForEach(geom.carbsDots, id: \.rect.minX) { info in
                    if let string = info.text, let textRect = info.textRect {
                        Text(string)
                            .rotationEffect(Angle(degrees: -90))
                            .font(geom.bolusFont)
                            .position(
                                CGPoint(x: textRect.midX, y: textRect.midY)
                            )
                    }
                }
            } else {
                ForEach(geom.carbsDots, id: \.rect.minX) { info in
                    if let string = info.text, let textRect = info.textRect {
                        Text(string).font(geom.bolusFont)
                            .position(
                                CGPoint(x: textRect.midX, y: textRect.midY)
                            )
                    }
                }
            }
        }
    }

    private var fpuView: some View {
        ZStack {
            let fpuPath = geom.fpuPath
            fpuPath.fill(data.useCarbBars ? .clear : Color.loopYellow)
            fpuPath.stroke(data.useCarbBars ? Color.loopYellow : Color.primary, lineWidth: data.useCarbBars ? 1.5 : 0.3)

            if data.useCarbBars, data.fpuAmounts {
                ForEach(geom.fpuDots, id: \.rect.minX) { info in
                    if let string = info.text, let textRect = info.textRect {
                        let position = textRect.origin
                        Text(string)
                            .rotationEffect(Angle(degrees: -90))
                            .font(geom.bolusFont)
                            .position(position)
                    }
                }
            } else if data.fpuAmounts {
                ForEach(geom.fpuDots, id: \.rect.minX) { info in
                    if let string = info.text, let textRect = info.textRect {
                        let position = textRect.origin
                        Text(string)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .position(position)
                    }
                }
            }
        }
    }

    private var tempTargetsView: some View {
        ZStack {
            geom.tempTargetsPath
                .fill(Color.tempBasal.opacity(0.5))
            geom.tempTargetsPath
                .stroke(Color.basal.opacity(0.5), lineWidth: 1)
        }
    }

    private var overridesView: some View {
        ZStack {
            geom.overridesPath
                .fill(Color.violet.opacity(colorScheme == .light ? 0.3 : 0.6))
            geom.overridesPath
                .stroke(Color.violet.opacity(0.7), lineWidth: 1)
        }
    }

    private var predictionsView: some View {
        Group {
            Path { path in
                for rect in geom.predictionDotsIOB {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.insulin.opacity(colorScheme == .dark ? 0.8 : 0.9))

            Path { path in
                for rect in geom.predictionDotsCOB {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.loopYellow.opacity(colorScheme == .dark ? 0.8 : 0.9))

            Path { path in
                for rect in geom.predictionDotsZT {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.zt.opacity(colorScheme == .dark ? 0.8 : 0.9))

            Path { path in
                for rect in geom.predictionDotsUAM {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.uam.opacity(colorScheme == .dark ? 0.8 : 0.9))
        }
    }
}
