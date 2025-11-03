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

typealias GlucosePeak = (
    yStart: CGFloat,
    yEnd: CGFloat,
    xStart: CGFloat,
    xEnd: CGFloat,
    textX: CGFloat,
    textY: CGFloat,
    glucose: Int,
    type: ExtremumType
)

struct MainChartView: View {
    let data: ChartModel
    @Binding var triggerUpdate: Bool

    enum Config {
        static let endID = "End"
        static let basalHeight: CGFloat = 60
        static let topYPadding: CGFloat = 55
        static let bottomPadding: CGFloat = 20
        static let legendBottomPadding: CGFloat = 8 // without insulin activity: additional legend padding
        static let activityChartHeight: CGFloat = 80
        static let activityChartTopGap: CGFloat = 20 // gap between main chart and activity chart, with legend inside
        static let mainChartBottomPaddingWithActivity: CGFloat = Config.bottomPadding + Config.activityChartHeight + Config
            .activityChartTopGap
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
        static let carbOffset: CGFloat = 10
        static let insulinOffset: CGFloat = 15
        static let pointSizeHeight: Double = 5
        static let pointSizeHeightCarbs: Double = 5
        static let bolusHeight: Decimal = 45
        static let carbHeight: Decimal = 45
        static let carbWidth: CGFloat = 5
    }

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

    @State private var glucoseDots: [(rect: CGRect, glucose: Int?)] = []
    @State private var activityDots: [CGPoint] = []
    @State private var activityZeroPointY: CGFloat? = nil
    @State private var cobDots: [(CGPoint, IOBData)] = []
    @State private var cobZeroPointY: CGFloat? = nil
    @State private var manualGlucoseDots: [CGRect] = []
    @State private var announcementDots: [AnnouncementDot] = []
    @State private var announcementPath = Path()
    @State private var manualGlucoseDotsCenter: [CGRect] = []
    @State private var unSmoothedGlucoseDots: [CGRect] = []
    @State private var predictionDots: [PredictionType: [CGRect]] = [:]
    @State private var bolusDots: [DotInfo] = []
    @State private var bolusPath = Path()
    @State private var tempBasalPath = Path()
    @State private var regularBasalPath = Path()
    @State private var tempTargetsPath = Path()
    @State private var overridesPath = Path()
    @State private var suspensionsPath = Path()
    @State private var carbsDots: [DotInfo] = []
    @State private var carbsPath = Path()
    @State private var fpuDots: [DotInfo] = []
    @State private var fpuPath = Path()
    @State private var glucoseYRange: GlucoseYRange = (0, 0, 0, 0)
    @State private var offset: CGFloat = 0
    @State private var cachedMaxBasalRate: Decimal?
    @State private var activityChartMinMax: (Double, Double) = (0, 1)
    @State private var cobChartMinMax: (Double, Double) = (0, 1)
    @State private var peakActivity_1unit: Double = 0.0
    @State private var peakActivity_1unit_y: CGFloat = 0.0
    @State private var peakActivity_maxBolus: Double = 0.0
    @State private var peakActivity_maxBolus_y: CGFloat = 0.0
    @State private var peakActivity_maxIOB: Double = 0.0
    @State private var peakActivity_maxIOB_y: CGFloat = 0.0
    @State private var maxActivityInData: Decimal? = nil
    @State private var horizontalGrid: [(CGFloat, Int)] = []
    @State private var lowThresholdLine: (CGFloat, Int)? = nil
    @State private var highThresholdLine: (CGFloat, Int)? = nil
    @State private var glucosePeaks: [GlucosePeak] = []

    @State private var geometriesReady = false

    @State private var firstHourDate = Date()
    @State private var oneSecondWidth: CGFloat = 0
    @State private var additionalWidth: CGFloat = 0
    @State private var fullGlucoseWidth: CGFloat = 0
    @State private var firstHourPosition: CGFloat = 0
    @State private var currentTimeX: CGFloat = 0

    private let calculationQueue = DispatchQueue(label: "MainChartView.calculationQueue")

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var date24Formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.setLocalizedDateFormatFromTemplate("HH")
        return formatter
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var dotGlucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }

    private var mmolDotGlucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }

    private var carbsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var fetchedTargetFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if data.units == .mmolL {
            formatter.maximumFractionDigits = 1
        } else { formatter.maximumFractionDigits = 0 }
        return formatter
    }

    @State private var latestSize: CGSize = .zero
    @State private var cancellables = Set<AnyCancellable>()

    private let sizeChanges = PassthroughSubject<Void, Never>()
    private let externalUpdates = PassthroughSubject<Void, Never>() // ← NEW

    var body: some View {
        GeometryReader { geo in
            ZStack {
                yGridView(fullSize: geo.size)
                mainScrollView(fullSize: geo.size)
                if data.yGridLabels {
                    glucoseLabelsView(fullSize: geo.size)
                }
                if data.showInsulinActivity, data.insulinActivityLabels {
                    activityLabelsView(fullSize: geo.size)
                }
            }
            .onAppear {
                latestSize = geo.size
                sizeChanges.send(())
                subscribeToUpdates()
            }
            .onChange(of: geo.size) {
                latestSize = geo.size
                sizeChanges.send(())
            }
            .onChange(of: triggerUpdate) {
                externalUpdates.send(())
            }
            .onReceive(Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                sizeChanges.send(())
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

    private func mainScrollView(fullSize: CGSize) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { scroll in
                ZStack(alignment: .top) {
                    tempTargetsView().drawingGroup()
                    overridesView().drawingGroup()
                    basalView().drawingGroup()
                    if data.showInsulinActivity || data.showCobChart {
                        legendPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, 20)
                            .padding(.bottom, Config.bottomPadding + Config.legendBottomPadding + Config.activityChartHeight)
                    } else {
                        legendPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(.trailing, 20)
                            .padding(.bottom, Config.bottomPadding + Config.legendBottomPadding)
                    }
                    mainView(fullSize: fullSize).id(Config.endID)
                        .drawingGroup()
                        /* .onChange(of: data.glucose) { _ in
                             scroll.scrollTo(Config.endID, anchor: .trailing)
                         }
                         .onChange(of: data.suggestion) { _ in
                             scroll.scrollTo(Config.endID, anchor: .trailing)
                         }
                         .onChange(of: data.tempBasals) { _ in
                             scroll.scrollTo(Config.endID, anchor: .trailing)
                         } */
                        .onChange(of: data.screenHours) {
                            DispatchQueue.main.async {
                                scroll.scrollTo(Config.endID, anchor: .trailing)
                            }
                        }
                        .onChange(of: geometriesReady) {
                            DispatchQueue.main.async {
                                scroll.scrollTo(Config.endID, anchor: .trailing)
                            }
                        }
                        .onAppear {
                            DispatchQueue.main.async {
                                scroll.scrollTo(Config.endID, anchor: .trailing)
                            }
                        }
                }
            }
        }
    }

    private func yGridView(fullSize: CGSize) -> some View {
        let useColour = data.displayYgridLines ? Color.secondary : Color.clear
        return ZStack {
            if data.displayYgridLines {
                Path { path in
                    for (line, _) in horizontalGrid {
                        path.move(to: CGPoint(x: 0, y: line))
                        path.addLine(to: CGPoint(x: fullSize.width, y: line))
                    }
                }.stroke(useColour, lineWidth: 0.15)
            }

            // in-range highlight
            if data.inRangeAreaFill {
                if let (highLineY, _) = highThresholdLine,
                   let (lowLineY, _) = lowThresholdLine
                {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: highLineY))
                        path.addLine(to: CGPoint(x: fullSize.width, y: highLineY))
                        path.addLine(to: CGPoint(x: fullSize.width, y: lowLineY))
                        path.addLine(to: CGPoint(x: 0, y: lowLineY))
                        path.addLine(to: CGPoint(x: 0, y: highLineY))
                    }.fill(IAPSconfig.inRangeBackground).opacity(colorScheme == .dark ? 0.15 : 0.20)
                }
            }

            // horizontal limits
            if data.thresholdLines {
                if let (highLineY, _) = highThresholdLine {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: highLineY))
                        path.addLine(to: CGPoint(x: fullSize.width, y: highLineY))
                    }.stroke(Color.loopYellow, lineWidth: 0.4).opacity(0.8)
                }
                if let (lowLineY, _) = lowThresholdLine {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: lowLineY))
                        path.addLine(to: CGPoint(x: fullSize.width, y: lowLineY))
                    }.stroke(Color.loopRed, lineWidth: 0.4).opacity(0.8)
                }
            }

            if data.showInsulinActivity || data.showCobChart {
                if data.secondaryChartBackdrop {
                    // background for COB/activity
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: fullSize.height - Config.bottomPadding))
                        path.addLine(to: CGPoint(x: fullSize.width, y: fullSize.height - Config.bottomPadding))
                        path
                            .addLine(to: CGPoint(
                                x: fullSize.width,
                                y: fullSize.height - Config.bottomPadding - Config.activityChartHeight
                            ))
                        path.addLine(to: CGPoint(x: 0, y: fullSize.height - Config.bottomPadding - Config.activityChartHeight))
                        path.addLine(to: CGPoint(x: 0, y: fullSize.height - Config.bottomPadding))
                    }.fill(IAPSconfig.activityBackground)
                }
            }

            if data.showInsulinActivity, data.insulinActivityGridLines {
                ForEach([(peakActivity_1unit_y, 1), (peakActivity_maxBolus_y, 2)], id: \.1) { yCoord, _ in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: yCoord))
                        path.addLine(to: CGPoint(x: fullSize.width, y: yCoord))
                    }.stroke(Color.secondary, lineWidth: 0.15)
                }
            }

            // thicker zero guideline for activity/COB
            if data.showInsulinActivity, data.insulinActivityGridLines, let yCoord = activityZeroPointY {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: yCoord))
                    path.addLine(to: CGPoint(x: fullSize.width, y: yCoord))
                }.stroke(Color.secondary, lineWidth: 0.4)
            }
        }
    }

    private func glucoseLabelsView(fullSize: CGSize) -> some View {
        ForEach(horizontalGrid, id: \.1) { (lineY, glucose) -> AnyView in
            let value = Double(glucose) *
                (data.units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

            Text(value == 0 ? "" : glucoseFormatter.string(from: value as NSNumber) ?? "")
                .position(CGPoint(x: fullSize.width - 12, y: lineY))
                .font(.bolusDotFont)
                .asAny()
        }
    }

    private func activityLabelsView(fullSize: CGSize) -> some View {
        ForEach(
            [
                (Decimal(1.0), peakActivity_1unit, peakActivity_1unit_y, 1),
                (data.maxBolus, peakActivity_maxBolus, peakActivity_maxBolus_y, 2)
            ],
            id: \.2
        ) { bolus, _, yCoord, _ in
            let value = bolus

            return HStack(spacing: 2) {
                Text(glucoseFormatter.string(from: value as NSNumber) ?? "").font(.bolusDotFont)
                Text("U").font(.bolusDotFont.smallCaps()) // .foregroundStyle(Color.secondary)
            }.foregroundStyle(Color(.insulin).opacity(0.8))
                .position(CGPoint(x: fullSize.width - 12, y: yCoord))
                .asAny()
        }
    }

    private func basalView() -> some View {
        ZStack {
            tempBasalPath.fill(Color.basal.opacity(0.5))
            tempBasalPath.stroke(Color.insulin, lineWidth: 1)
            regularBasalPath.stroke(Color.insulin, style: StrokeStyle(lineWidth: 0.7, dash: [4]))
            suspensionsPath.stroke(Color.loopGray.opacity(0.7), style: StrokeStyle(lineWidth: 0.7)).scaleEffect(x: 1, y: -1)
            suspensionsPath.fill(Color.loopGray.opacity(0.2)).scaleEffect(x: 1, y: -1)
        }
        .scaleEffect(x: 1, y: -1)
        .frame(
            width: fullGlucoseWidth + additionalWidth
        )
        .frame(maxHeight: Config.basalHeight)
        .background(Color.clear)
    }

    private func mainView(fullSize: CGSize) -> some View {
        Group {
            VStack {
                ZStack {
                    xGridView(fullSize: fullSize)
                    bolusView()
                    if data.smooth { unSmoothedGlucoseView() }
                    else { connectingGlucoseLinesView() }
                    glucoseView()
                    lowGlucoseView()
                    highGlucoseView()
                    if data.chartGlucosePeaks {
                        glucosePeaksView()
                    }
                    if data.showInsulinActivity {
                        activityView()
                    }
                    if data.showCobChart {
                        cobView()
                    }
                    carbsView() // has to be after activityView()
                    manualGlucoseView()
                    manualGlucoseCenterView()
                    announcementView()
                    if true || !data.hidePredictions {
                        predictionsView()
                    }
                    if data.fpus { fpuView() }
                }
                timeLabelsView()
            }
        }
        .frame(
            width: fullGlucoseWidth + additionalWidth
        )
    }

    @Environment(\.colorScheme) var colorScheme

    private func xGridView(fullSize: CGSize) -> some View {
        let useColour = data.displayXgridLines ? Color.secondary : Color.clear
        return ZStack {
            Path { path in
                for hour in 0 ..< data.hours + data.hours {
                    if data.screenHours < 12 || hour % 2 == 0 {
                        // only show every second line if screenHours is too big
                        let x = firstHourPosition +
                            oneSecondWidth *
                            CGFloat(hour) * CGFloat(1.hours.timeInterval)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: fullSize.height - 20))
                    }
                }
            }
            .stroke(useColour, lineWidth: 0.15)

            Path { path in // vertical timeline
                path.move(to: CGPoint(x: currentTimeX, y: 0))
                path.addLine(to: CGPoint(x: currentTimeX, y: fullSize.height - 20))
            }
            .stroke(
                colorScheme == .dark ? IAPSconfig.chartBackgroundLight : IAPSconfig.chartBackgroundDark,
                style: StrokeStyle(lineWidth: 0.5, dash: [5])
            )
        }
    }

    private func timeLabelsView() -> some View {
        let format = date24Formatter
        return ZStack {
            ForEach(0 ..< data.hours + data.hours, id: \.hours) { hour in
                if data.screenHours >= 12 && hour % 2 == 1 {
                    // only show every second time label if screenHours is too big
                    EmptyView()
                } else {
                    Text(format.string(from: firstHourDate.addingTimeInterval(hour.hours.timeInterval)))
                        .font(.chartTimeFont)
                        .position(
                            x: firstHourPosition +
                                oneSecondWidth *
                                CGFloat(hour) * CGFloat(1.hours.timeInterval),
                            y: 10.0
                        )
                        .foregroundColor(.secondary)
                }
            }
        }.frame(maxHeight: 20)
    }

    private func lowGlucoseView() -> some View {
        Path { path in
            for rect in glucoseDots {
                if let glucose = rect.glucose, Decimal(glucose) <= data.lowGlucose {
                    path.addEllipse(in: rect.rect)
                }
            }
        }.fill(Color.red)
    }

    private func glucoseView() -> some View {
        Path { path in
            for rect in glucoseDots {
                if let glucose = rect.glucose, Decimal(glucose) > data.lowGlucose,
                   Decimal(glucose) < data.highGlucose
                {
                    path.addEllipse(in: rect.rect)
                }
            }
        }.fill(Color(.darkGreen))
    }

    private func highGlucoseView() -> some View {
        Path { path in
            for rect in glucoseDots {
                if let glucose = rect.glucose, Decimal(glucose) >= data.highGlucose {
                    path.addEllipse(in: rect.rect)
                }
            }
        }.fill(.orange)
    }

    private func glucosePeaksView() -> some View {
        ForEach(glucosePeaks, id: \.3) { yStart, yEnd, xStart, xEnd, textX, textY, glucose, _ in
            let value = Double(glucose) *
                (data.units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

            let formatter = data.units == .mmolL ? mmolDotGlucoseFormatter : dotGlucoseFormatter

            Group {
                Path { path in
                    path.move(to: CGPoint(x: xStart, y: yStart))
                    path.addLine(to: CGPoint(x: xEnd, y: yEnd))
                }
                .stroke(Color.secondary, lineWidth: 0.75)
                .opacity(0.75)
                .mask(
                    // the line goes from the center of the bg dot to the center of the text label
                    // because of this mask (which is a "copy" of the actual label below) - the line doesn't go under the label, even though it's semi-transparent
                    // a simpler solution is to fill the rectangle below with 1.0 opacity - but needs a better colour
                    ZStack {
                        Color.white // allow everywhere by default
                        Text(value == 0 ? "" : formatter.string(from: value as NSNumber) ?? "")
                            .font(.glucoseDotFont)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.black) // cut out this area
                            )
                            .position(CGPoint(x: textX, y: textY))
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                )

                let glucoseDecimal = Decimal(glucose)
                let fillColour =
                    glucoseDecimal < data.lowGlucose ? Color.loopRed.opacity(0.4)
                        : glucoseDecimal > data.highGlucose ? Color.loopYellow.opacity(0.4)
                        : colorScheme == .dark ? Color.darkGreen.opacity(0.6) : Color.darkGreen.opacity(0.4)

                ZStack {
                    Text(value == 0 ? "" : formatter.string(from: value as NSNumber) ?? "")
                        .font(.glucoseDotFont)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(fillColour)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.primary, lineWidth: 0.5)
                                .opacity(0.9)
                        )
                }
                .position(CGPoint(x: textX, y: textY))
            }
            .asAny()
        }
    }

    private func activityView() -> some View {
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
            guard activityDots.count >= 2 else { return }
            guard let zeroY = self.activityZeroPointY else { return }

            var hasPositiveValues = false

            for i in 0 ..< activityDots.count {
                let point = activityDots[i]

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
                let lastPoint = activityDots.last!
                path.addLine(to: CGPoint(x: lastPoint.x, y: zeroY))
                path.closeSubpath()
            }
        }
    }

    private func negativeActivityFillPath() -> Path {
        Path { path in
            guard activityDots.count >= 2 else { return }
            guard let zeroY = self.activityZeroPointY else { return }

            var hasNegativeValues = false

            for i in 0 ..< activityDots.count {
                let point = activityDots[i]

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
                let lastPoint = activityDots.last!
                path.addLine(to: CGPoint(x: lastPoint.x, y: zeroY))
                path.closeSubpath()
            }
        }
    }

    private func activityStrokePath() -> Path {
        Path { path in
            guard activityDots.count >= 2 else { return }
            path.move(to: activityDots[0])
            for point in activityDots.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func cobView() -> some View {
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
            guard let cobZeroPointY = self.cobZeroPointY else { return }
            var isDrawing = false

            for (point, cob) in cobDots.reversed() {
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
                if isDrawing, let (latest, _) = cobDots.first {
                    path.addLine(to: CGPoint(x: latest.x, y: cobZeroPointY))
                }
            }
        }
    }

    private func connectingGlucoseLinesView() -> some View {
        Path { path in
            var lines: [CGPoint] = []
            for rect in glucoseDots {
                lines.append(CGPoint(x: rect.rect.midX, y: rect.rect.midY))
            }
            path.addLines(lines)
        }
        .stroke(Color.primary, lineWidth: 0.25)
    }

    private func manualGlucoseView() -> some View {
        Path { path in
            for rect in manualGlucoseDots {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.gray)
    }

    private func announcementView() -> some View {
        ZStack {
            ForEach(announcementDots, id: \.rect.minX) { info -> AnyView in
                let position = CGPoint(x: info.rect.midX, y: info.rect.maxY - Config.owlOffset)
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

    private func manualGlucoseCenterView() -> some View {
        Path { path in
            for rect in manualGlucoseDotsCenter {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.red)
    }

    private func unSmoothedGlucoseView() -> some View {
        Path { path in
            var lines: [CGPoint] = []
            for rect in unSmoothedGlucoseDots {
                lines.append(CGPoint(x: rect.midX, y: rect.midY))
                path.addEllipse(in: rect)
            }
            path.addLines(lines)
        }
        .stroke(Color.secondary, lineWidth: 0.5)
    }

    private func bolusView() -> some View {
        ZStack {
            let bolusPath = data.useInsulinBars ? insulinBar() : bolusPath
            bolusPath.fill(Color.insulin)
            bolusPath.stroke(Color.primary, lineWidth: 0.3)

            if data.useInsulinBars {
                ForEach(bolusDots, id: \.rect.minX) { info -> AnyView in
                    let string = bolusFormatter.string(from: info.value as NSNumber) ?? ""
                    let stringLength = CGFloat(string.count) * 2
                    let position = CGPoint(x: info.rect.midX, y: info.rect.minY - (8 + stringLength + Config.pointSizeHeight))
                    Text(info.value >= data.minimumSMB ? string : "")
                        .rotationEffect(Angle(degrees: -90))
                        .font(bolusFont())
                        .position(position)
                        .asAny()
                }
            } else {
                ForEach(bolusDots, id: \.rect.minX) { info -> AnyView in
                    let position = CGPoint(x: info.rect.midX, y: info.rect.minY - 8)
                    return Text(info.value >= data.minimumSMB ? (bolusFormatter.string(from: info.value as NSNumber) ?? "") : "")
                        .font(.bolusDotFont)
                        .position(position)
                        .asAny()
                }
            }
        }
    }

    private func carbsView() -> some View {
        ZStack {
            let carbsPath = data.useCarbBars ? carbsBar(carbsDots) : carbsPath
            carbsPath.fill(Color.loopYellow)
            carbsPath.stroke(Color.primary, lineWidth: 0.3)

            if data.useCarbBars {
                ForEach(carbsDots, id: \.rect.minX) { info -> AnyView in
                    let string = carbsFormatter.string(from: info.value as NSNumber) ?? ""
                    let stringLength = CGFloat(string.count) * 2
                    let position = CGPoint(x: info.rect.midX, y: info.rect.maxY + (8 + stringLength + Config.pointSizeHeight))
                    Text(string)
                        .rotationEffect(Angle(degrees: -90))
                        .font(bolusFont())
                        .position(position)
                        .asAny()
                }
            } else {
                ForEach(carbsDots, id: \.rect.minX) { info -> AnyView in
                    let position = CGPoint(x: info.rect.midX, y: info.rect.maxY + 8)
                    return Text(carbsFormatter.string(from: info.value as NSNumber) ?? "").font(.carbsDotFont)
                        .position(position)
                        .asAny()
                }
            }
        }
    }

    private func fpuView() -> some View {
        ZStack {
            let fpuPath = data.useCarbBars ? carbsBar(fpuDots) : fpuPath
            fpuPath.fill(data.useCarbBars ? .clear : Color.loopYellow)
            fpuPath.stroke(data.useCarbBars ? Color.loopYellow : Color.primary, lineWidth: data.useCarbBars ? 1.5 : 0.3)

            if data.useCarbBars, data.fpuAmounts {
                ForEach(fpuDots, id: \.rect.minX) { info -> AnyView in
                    let string = carbsFormatter.string(from: info.value as NSNumber) ?? ""
                    let stringLength = CGFloat(string.count) * 2
                    let position = CGPoint(x: info.rect.midX, y: info.rect.maxY + (8 + stringLength + Config.pointSizeHeight))
                    Text(string)
                        .rotationEffect(Angle(degrees: -90))
                        .font(bolusFont())
                        .position(position)
                        .asAny()
                }
            } else if data.fpuAmounts {
                ForEach(fpuDots, id: \.rect.minX) { info -> AnyView in
                    let position = CGPoint(x: info.rect.midX, y: info.rect.maxY + 8)
                    return Text(carbsFormatter.string(from: info.value as NSNumber) ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .position(position)
                        .asAny()
                }
            }
        }
    }

    private func tempTargetsView() -> some View {
        ZStack {
            tempTargetsPath
                .fill(Color.tempBasal.opacity(0.5))
            tempTargetsPath
                .stroke(Color.basal.opacity(0.5), lineWidth: 1)
        }
    }

    private func overridesView() -> some View {
        ZStack {
            overridesPath
                .fill(Color.violet.opacity(colorScheme == .light ? 0.3 : 0.6))
            overridesPath
                .stroke(Color.violet.opacity(0.7), lineWidth: 1)
        }
    }

    private func predictionsView() -> some View {
        Group {
            Path { path in
                for rect in predictionDots[.iob] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.insulin)

            Path { path in
                for rect in predictionDots[.cob] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.loopYellow)

            Path { path in
                for rect in predictionDots[.zt] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.zt)

            Path { path in
                for rect in predictionDots[.uam] ?? [] {
                    path.addEllipse(in: rect)
                }
            }.fill(Color.uam)
        }
    }
}

// MARK: - Calculations

extension MainChartView {
    private func update(fullSize: CGSize) {
        let geom = CalculatedGeometries(fullSize: fullSize, data: data)

        DispatchQueue.main.async {
            self.firstHourDate = geom.firstHourDate
            self.oneSecondWidth = geom.oneSecondWidth
            self.additionalWidth = geom.additionalWidth
            self.fullGlucoseWidth = geom.fullGlucoseWidth
            self.firstHourPosition = geom.firstHourPosition
            self.currentTimeX = geom.currentTimeX

            self.peakActivity_1unit = geom.peakActivity_1unit
            self.peakActivity_1unit_y = geom.peakActivity_1unit_y
            self.peakActivity_maxBolus = geom.peakActivity_maxBolus
            self.peakActivity_maxBolus_y = geom.peakActivity_maxBolus_y
            self.peakActivity_maxIOB = geom.peakActivity_maxIOB
            self.peakActivity_maxIOB_y = geom.peakActivity_maxIOB_y
            self.maxActivityInData = geom.maxActivityInData

            self.activityChartMinMax = geom.activityChartMinMax
            self.cobChartMinMax = geom.cobChartMinMax

            self.predictionDots[.iob] = geom.predictionDotsIOB
            self.predictionDots[.cob] = geom.predictionDotsCOB
            self.predictionDots[.zt] = geom.predictionDotsZT
            self.predictionDots[.uam] = geom.predictionDotsUAM

            self.glucoseYRange = geom.glucoseYRange
            self.glucoseDots = geom.glucoseDots

            self.activityDots = geom.activityDots
            self.activityZeroPointY = geom.activityZeroPointY

            self.cobDots = geom.cobDots
            self.cobZeroPointY = geom.cobZeroPointY
            self.manualGlucoseDots = geom.manualGlucoseDots
            self.manualGlucoseDotsCenter = geom.manualGlucoseDotsCenter

            self.announcementDots = geom.announcementDots
            self.announcementPath = geom.announcementPath
            self.unSmoothedGlucoseDots = geom.unSmoothedGlucoseDots

            self.bolusDots = geom.bolusDots
            self.bolusPath = geom.bolusPath

            self.carbsDots = geom.carbsDots
            self.carbsPath = geom.carbsPath

            self.fpuDots = geom.fpuDots
            self.fpuPath = geom.fpuPath

            self.tempTargetsPath = geom.tempTargetsPath
            self.overridesPath = geom.overridesPath

            self.tempBasalPath = geom.tempBasalPath
            self.regularBasalPath = geom.regularBasalPath

            self.suspensionsPath = geom.suspensionsPath

            self.horizontalGrid = geom.horizontalGrid
            self.lowThresholdLine = geom.lowThresholdLine
            self.highThresholdLine = geom.highThresholdLine

            self.glucosePeaks = geom.glucosePeaks

            self.geometriesReady = true
        }
    }

    private func ping<T: Equatable>(_ p: Published<T>.Publisher) -> AnyPublisher<Void, Never> {
        p.removeDuplicates()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    private func subscribeToUpdates() {
        let publishers: [AnyPublisher<Void, Never>] = [
            ping(data.$screenHours),
            ping(data.$showInsulinActivity),
            ping(data.$insulinActivityGridLines),
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
            ping(data.$overrideHistory),
            // ---
            sizeChanges.eraseToAnyPublisher(),
            externalUpdates.eraseToAnyPublisher()
        ]

        // Merge + debounce + update once
        Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(100), scheduler: calculationQueue)
            .receive(on: calculationQueue)
            .sink { _ in
                update(fullSize: latestSize)
            }
            .store(in: &cancellables)
    }

    // An InsulinBarMark of sorts
    private func insulinBar() -> Path {
        Path { path in
            for dot in bolusDots {
                let rect = dot.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY + MainChartView.Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY - MainChartView.Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - MainChartView.Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + MainChartView.Config.pointSizeHeight))
            }
        }
    }

    // A BarMark for Carbs
    private func carbsBar(_ dots: [DotInfo]) -> Path {
        Path { path in
            for dot in dots {
                let rect = dot.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.minY - MainChartView.Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + MainChartView.Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + MainChartView.Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.minY - MainChartView.Config.pointSizeHeight))
            }
        }
    }

    private func bolusFont() -> Font {
        var size = CGFloat(12)
        switch data.screenHours {
        case 12:
            size = 9
        case 24:
            size = 7
        default:
            size = 11
        }
        return Font.custom("BolusDotFont", fixedSize: size)
    }
}
