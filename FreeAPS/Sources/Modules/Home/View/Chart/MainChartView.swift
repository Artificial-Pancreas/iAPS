import Algorithms
import SwiftDate
import SwiftUI

private enum PredictionType: Hashable {
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

struct MainChartView: View {
    let data: ChartModel
    @Binding var triggerUpdate: Bool

    private enum Config {
        static let endID = "End"
        static let basalHeight: CGFloat = 60
        static let topYPadding: CGFloat = 75
        static let bottomYPadding: CGFloat = 20
        static let minAdditionalWidth: CGFloat = 150
        static let maxGlucose = 270
        static let minGlucose = 0 // 45
        static let yLinesCount = 5
        static let glucoseScale: CGFloat = 2 // default 2
        static let bolusSize: CGFloat = 8
        static let bolusScale: CGFloat = 2.5
        static let carbsSize: CGFloat = 10
        static let fpuSize: CGFloat = 5
        static let carbsScale: CGFloat = 0.3
        static let fpuScale: CGFloat = 1
        static let announcementSize: CGFloat = 8
        static let announcementScale: CGFloat = 2.5
        static let owlSeize: CGFloat = 20
        static let glucoseSize: CGFloat = 4
        static let owlOffset: CGFloat = 100
        static let carbOffset: CGFloat = 15
        static let insulinOffset: CGFloat = 15
        static let pointSizeHeight: Double = 5
        static let pointSizeHeightCarbs: Double = 5
        static let bolusHeight: Decimal = 45
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

    @State var didAppearTrigger = false
    @State private var glucoseDots: [CGRect] = []
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

    @Environment(\.horizontalSizeClass) var hSizeClass
    @Environment(\.verticalSizeClass) var vSizeClass

    var body: some View {
        GeometryReader { geo in
            ZStack {
                yGridView(fullSize: geo.size)
                mainScrollView(fullSize: geo.size)
                glucoseLabelsView(fullSize: geo.size)
            }
            .onChange(of: hSizeClass) {
                update(fullSize: geo.size)
            }
            .onChange(of: vSizeClass) {
                update(fullSize: geo.size)
            }
            .onChange(of: data.screenHours) {
                update(fullSize: geo.size)
            }
            .onReceive(
                Foundation.NotificationCenter.default
                    .publisher(for: UIDevice.orientationDidChangeNotification)
            ) { _ in
                update(fullSize: geo.size)
            }
        }
    }

    var legendPanel: some View {
        ZStack {
            HStack {
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
            .padding(.bottom, 8)
        }
    }

    private func mainScrollView(fullSize: CGSize) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ScrollViewReader { scroll in
                ZStack(alignment: .top) {
                    tempTargetsView(fullSize: fullSize).drawingGroup()
                    overridesView(fullSize: fullSize).drawingGroup()
                    basalView(fullSize: fullSize).drawingGroup()
                    legendPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 20).padding(.bottom, 20)
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
                            scroll.scrollTo(Config.endID, anchor: .trailing)
                        }
                        .onAppear {
                            // add trigger to the end of main queue
                            DispatchQueue.main.async {
                                scroll.scrollTo(Config.endID, anchor: .trailing)
                                didAppearTrigger = true
                            }
                        }
                }
            }
        }
    }

    private func yGridView(fullSize: CGSize) -> some View {
        let useColour = data.displayYgridLines ? Color.secondary : Color.clear
        return ZStack {
            Path { path in
                let range = glucoseYRange
                let step = (range.maxY - range.minY) / CGFloat(Config.yLinesCount)
                for line in 0 ... Config.yLinesCount {
                    path.move(to: CGPoint(x: 0, y: range.minY + CGFloat(line) * step))
                    path.addLine(to: CGPoint(x: fullSize.width, y: range.minY + CGFloat(line) * step))
                }
            }.stroke(useColour, lineWidth: 0.15)

            // horizontal limits
            if data.thresholdLines {
                let range = glucoseYRange
                let topstep = (range.maxY - range.minY) / CGFloat(range.maxValue - range.minValue) *
                    (CGFloat(range.maxValue) - CGFloat(data.highGlucose))
                if CGFloat(range.maxValue) > CGFloat(data.highGlucose) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: range.minY + topstep))
                        path.addLine(to: CGPoint(x: fullSize.width, y: range.minY + topstep))
                    }.stroke(Color.loopYellow, lineWidth: 0.5) // .StrokeStyle(lineWidth: 0.5, dash: [5])
                }
                let yrange = glucoseYRange
                let bottomstep = (yrange.maxY - yrange.minY) / CGFloat(yrange.maxValue - yrange.minValue) *
                    (CGFloat(yrange.maxValue) - CGFloat(data.lowGlucose))
                if CGFloat(yrange.minValue) < CGFloat(data.lowGlucose) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: yrange.minY + bottomstep))
                        path.addLine(to: CGPoint(x: fullSize.width, y: yrange.minY + bottomstep))
                    }.stroke(Color.loopRed, lineWidth: 0.5)
                }
            }
        }
    }

    private func glucoseLabelsView(fullSize: CGSize) -> some View {
        ForEach(0 ..< Config.yLinesCount + 1, id: \.self) { line -> AnyView in
            let range = glucoseYRange
            let yStep = (range.maxY - range.minY) / CGFloat(Config.yLinesCount)
            let valueStep = Double(range.maxValue - range.minValue) / Double(Config.yLinesCount)
            let value = round(Double(range.maxValue) - Double(line) * valueStep) *
                (data.units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

            return Text(glucoseFormatter.string(from: value as NSNumber) ?? "")
                .position(CGPoint(x: fullSize.width - 12, y: range.minY + CGFloat(line) * yStep))
                .font(.bolusDotFont)
                .asAny()
        }
    }

    private func basalView(fullSize: CGSize) -> some View {
        ZStack {
            tempBasalPath.fill(Color.basal.opacity(0.5))
            tempBasalPath.stroke(Color.insulin, lineWidth: 1)
            regularBasalPath.stroke(Color.insulin, style: StrokeStyle(lineWidth: 0.7, dash: [4]))
            suspensionsPath.stroke(Color.loopGray.opacity(0.7), style: StrokeStyle(lineWidth: 0.7)).scaleEffect(x: 1, y: -1)
            suspensionsPath.fill(Color.loopGray.opacity(0.2)).scaleEffect(x: 1, y: -1)
        }
        .scaleEffect(x: 1, y: -1)
        .frame(width: fullGlucoseWidth(viewWidth: fullSize.width) + additionalWidth(viewWidth: fullSize.width))
        .frame(maxHeight: Config.basalHeight)
        .background(Color.clear)
        .onChange(of: data.tempBasals) {
            calculateBasalPoints(fullSize: fullSize)
        }
        .onChange(of: data.suspensions) {
            calculateSuspensions(fullSize: fullSize)
        }
        .onChange(of: data.maxBasal) {
            calculateBasalPoints(fullSize: fullSize)
        }
        .onChange(of: data.autotunedBasalProfile) {
            calculateBasalPoints(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateBasalPoints(fullSize: fullSize)
        }
    }

    private func mainView(fullSize: CGSize) -> some View {
        Group {
            VStack {
                ZStack {
                    xGridView(fullSize: fullSize)
                    carbsView(fullSize: fullSize)
                    bolusView(fullSize: fullSize)
                    if data.smooth { unSmoothedGlucoseView(fullSize: fullSize) }
                    else { connectingGlucoseLinesView(fullSize: fullSize) }
                    glucoseView(fullSize: fullSize)
                    manualGlucoseView(fullSize: fullSize)
                    manualGlucoseCenterView(fullSize: fullSize)
                    announcementView(fullSize: fullSize)
                    predictionsView(fullSize: fullSize)
                    if data.fpus { fpuView(fullSize: fullSize) }
                }
                timeLabelsView(fullSize: fullSize)
            }
        }
        .frame(width: fullGlucoseWidth(viewWidth: fullSize.width) + additionalWidth(viewWidth: fullSize.width))
    }

    @Environment(\.colorScheme) var colorScheme

    private func xGridView(fullSize: CGSize) -> some View {
        let useColour = data.displayXgridLines ? Color.secondary : Color.clear
        return ZStack {
            Path { path in
                for hour in 0 ..< data.hours + data.hours {
                    if data.screenHours < 12 || hour % 2 == 0 {
                        // only show every second line if screenHours is too big
                        let x = firstHourPosition(viewWidth: fullSize.width) +
                            oneSecondStep(viewWidth: fullSize.width) *
                            CGFloat(hour) * CGFloat(1.hours.timeInterval)
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: fullSize.height - 20))
                    }
                }
            }
            .stroke(useColour, lineWidth: 0.15)

            Path { path in // vertical timeline
                let x = timeToXCoordinate(data.timerDate.timeIntervalSince1970, fullSize: fullSize)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: fullSize.height - 20))
            }
            .stroke(
                colorScheme == .dark ? Color.white : Color.black,
                style: StrokeStyle(lineWidth: 0.5, dash: [5])
            )
        }
    }

    private func timeLabelsView(fullSize: CGSize) -> some View {
        let format = date24Formatter
        return ZStack {
            ForEach(0 ..< data.hours + data.hours, id: \.hours) { hour in
                if data.screenHours >= 12 && hour % 2 == 1 {
                    // only show every second time label if screenHours is too big
                    EmptyView()
                } else {
                    Text(format.string(from: firstHourDate().addingTimeInterval(hour.hours.timeInterval)))
                        .font(.chartTimeFont)
                        .position(
                            x: firstHourPosition(viewWidth: fullSize.width) +
                                oneSecondStep(viewWidth: fullSize.width) *
                                CGFloat(hour) * CGFloat(1.hours.timeInterval),
                            y: 10.0
                        )
                        .foregroundColor(.secondary)
                }
            }
        }.frame(maxHeight: 20)
    }

    private func glucoseView(fullSize: CGSize) -> some View {
        Path { path in
            for rect in glucoseDots {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.darkGreen)
        .onChange(of: data.glucose) {
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            update(fullSize: fullSize)
        }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            update(fullSize: fullSize)
        }
    }

    private func connectingGlucoseLinesView(fullSize: CGSize) -> some View {
        Path { path in
            var lines: [CGPoint] = []
            for rect in glucoseDots {
                lines.append(CGPoint(x: rect.midX, y: rect.midY))
            }
            path.addLines(lines)
        }
        .stroke(Color.loopGreen, lineWidth: 0.5)
        .onChange(of: data.glucose) {
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            update(fullSize: fullSize)
        }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            update(fullSize: fullSize)
        }
    }

    private func manualGlucoseView(fullSize: CGSize) -> some View {
        Path { path in
            for rect in manualGlucoseDots {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.gray)
        .onChange(of: data.isManual) {
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            update(fullSize: fullSize)
        }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            update(fullSize: fullSize)
        }
    }

    private func announcementView(fullSize: CGSize) -> some View {
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
        .onChange(of: data.announcement) {
            calculateAnnouncementDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateAnnouncementDots(fullSize: fullSize)
        }
    }

    private func manualGlucoseCenterView(fullSize: CGSize) -> some View {
        Path { path in
            for rect in manualGlucoseDotsCenter {
                path.addEllipse(in: rect)
            }
        }
        .fill(Color.red)

        .onChange(of: data.isManual) {
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            update(fullSize: fullSize)
        }
        .onReceive(
            Foundation.NotificationCenter.default
                .publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            update(fullSize: fullSize)
        }
    }

    private func unSmoothedGlucoseView(fullSize: CGSize) -> some View {
        Path { path in
            var lines: [CGPoint] = []
            for rect in unSmoothedGlucoseDots {
                lines.append(CGPoint(x: rect.midX, y: rect.midY))
                path.addEllipse(in: rect)
            }
            path.addLines(lines)
        }
        .stroke(Color.loopGray, lineWidth: 0.5)
        .onChange(of: data.glucose) {
            update(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            update(fullSize: fullSize)
        }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            update(fullSize: fullSize)
        }
    }

    private func bolusView(fullSize: CGSize) -> some View {
        ZStack {
            let bolusPath = data.useInsulinBars ? insulinBar() : bolusPath
            bolusPath.fill(Color.insulin)
            bolusPath.stroke(Color.primary, lineWidth: 0.3)

            if data.useInsulinBars {
                ForEach(bolusDots, id: \.rect.minX) { info -> AnyView in
                    let string = bolusFormatter.string(from: info.value as NSNumber) ?? ""
                    let stringLength = CGFloat(string.count) * 2
                    let position = CGPoint(x: info.rect.midX, y: info.rect.minY - (8 + stringLength + Config.pointSizeHeight))
                    Text(info.value >= data.minimumSMB ? (bolusFormatter.string(from: info.value as NSNumber) ?? "") : "")
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
        .onChange(of: data.boluses) {
            calculateBolusDots(fullSize: fullSize)
        }
        .onChange(of: data.useInsulinBars) {
            calculateBolusDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateBolusDots(fullSize: fullSize)
        }
    }

    private func carbsView(fullSize: CGSize) -> some View {
        ZStack {
            carbsPath
                .fill(Color.loopYellow)
            carbsPath
                .stroke(Color.primary, lineWidth: 0.5)

            ForEach(carbsDots, id: \.rect.minX) { info -> AnyView in
                let position = CGPoint(x: info.rect.midX, y: info.rect.maxY + 8)
                return Text(carbsFormatter.string(from: info.value as NSNumber) ?? "").font(.carbsDotFont)
                    .position(position)
                    .asAny()
            }
        }
        .onChange(of: data.carbs) {
            calculateCarbsDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateCarbsDots(fullSize: fullSize)
        }
    }

    private func fpuView(fullSize: CGSize) -> some View {
        ZStack {
            fpuPath
                .fill(Color(.systemGray3))
            fpuPath
                .stroke(Color.loopYellow, lineWidth: 1)

            if data.fpuAmounts {
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
        .onChange(of: data.carbs) {
            calculateFPUsDots(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateFPUsDots(fullSize: fullSize)
        }
    }

    private func tempTargetsView(fullSize: CGSize) -> some View {
        ZStack {
            tempTargetsPath
                .fill(Color.tempBasal.opacity(0.5))
            tempTargetsPath
                .stroke(Color.basal.opacity(0.5), lineWidth: 1)
        }
        .onChange(of: data.glucose) {
            calculateTempTargetsRects(fullSize: fullSize)
        }
        .onChange(of: data.tempTargets) {
            calculateTempTargetsRects(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateTempTargetsRects(fullSize: fullSize)
        }
    }

    private func overridesView(fullSize: CGSize) -> some View {
        ZStack {
            overridesPath
                .fill(Color.violet.opacity(colorScheme == .light ? 0.3 : 0.6))
            overridesPath
                .stroke(Color.violet.opacity(0.7), lineWidth: 1)
        }
        .onChange(of: data.glucose) {
            calculateOverridesRects(fullSize: fullSize)
        }
        .onChange(of: data.suggestion) {
            calculateOverridesRects(fullSize: fullSize)
        }
        .onChange(of: data.overrideHistory) {
            calculateOverridesRects(fullSize: fullSize)
        }
        .onChange(of: triggerUpdate) {
            calculateOverridesRects(fullSize: fullSize)
        }
        .onChange(of: didAppearTrigger) {
            calculateOverridesRects(fullSize: fullSize)
        }
    }

    private func predictionsView(fullSize: CGSize) -> some View {
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
        .onChange(of: data.suggestion) {
            update(fullSize: fullSize)
        }
    }
}

// MARK: - Calculations

extension MainChartView {
    private func update(fullSize: CGSize) {
        calculatePredictionDots(fullSize: fullSize, type: .iob)
        calculatePredictionDots(fullSize: fullSize, type: .cob)
        calculatePredictionDots(fullSize: fullSize, type: .zt)
        calculatePredictionDots(fullSize: fullSize, type: .uam)
        calculateGlucoseDots(fullSize: fullSize)
        calculateManualGlucoseDots(fullSize: fullSize)
        calculateManualGlucoseDotsCenter(fullSize: fullSize)
        calculateAnnouncementDots(fullSize: fullSize)
        calculateUnSmoothedGlucoseDots(fullSize: fullSize)
        calculateBolusDots(fullSize: fullSize)
        calculateCarbsDots(fullSize: fullSize)
        calculateFPUsDots(fullSize: fullSize)
        calculateTempTargetsRects(fullSize: fullSize)
        calculateOverridesRects(fullSize: fullSize)
        calculateBasalPoints(fullSize: fullSize)
        calculateSuspensions(fullSize: fullSize)
        print("Updating Main Chart")
    }

    private func calculateGlucoseDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = data.glucose.concurrentMap { value -> CGRect in
                let position = glucoseToCoordinate(value, fullSize: fullSize)
                return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: Config.glucoseSize)
            }

            let range = self.getGlucoseYRange(fullSize: fullSize)

            DispatchQueue.main.async {
                glucoseYRange = range
                glucoseDots = dots
            }
        }
    }

    private func calculateManualGlucoseDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = data.isManual.concurrentMap { value -> CGRect in
                let position = glucoseToCoordinate(value, fullSize: fullSize)
                return CGRect(x: position.x - 6, y: position.y - 6, width: 14, height: 14)
            }

            let range = self.getGlucoseYRange(fullSize: fullSize)

            DispatchQueue.main.async {
                glucoseYRange = range
                manualGlucoseDots = dots
            }
        }
    }

    private func calculateManualGlucoseDotsCenter(fullSize: CGSize) {
        calculationQueue.async {
            let dots = data.isManual.concurrentMap { value -> CGRect in
                let position = glucoseToCoordinate(value, fullSize: fullSize)
                return CGRect(x: position.x - 4, y: position.y - 4, width: 10, height: 10)
            }

            let range = self.getGlucoseYRange(fullSize: fullSize)

            DispatchQueue.main.async {
                glucoseYRange = range
                manualGlucoseDotsCenter = dots
            }
        }
    }

    private func calculateAnnouncementDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = data.announcement.map { value -> AnnouncementDot in
                let center = timeToInterpolatedPoint(value.createdAt.timeIntervalSince1970, fullSize: fullSize)
                let size = Config.announcementSize * Config.announcementScale
                let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                let note = value.notes
                return AnnouncementDot(rect: rect, value: 10, note: note)
            }
            let path = Path { path in
                for dot in dots {
                    path.addEllipse(in: dot.rect)
                }
            }
            let range = self.getGlucoseYRange(fullSize: fullSize)

            DispatchQueue.main.async {
                glucoseYRange = range
                announcementDots = dots
                announcementPath = path
            }
        }
    }

    private func calculateUnSmoothedGlucoseDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = data.glucose.concurrentMap { value -> CGRect in
                let position = UnSmoothedGlucoseToCoordinate(value, fullSize: fullSize)
                return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
            }

            let range = self.getGlucoseYRange(fullSize: fullSize)

            DispatchQueue.main.async {
                glucoseYRange = range
                unSmoothedGlucoseDots = dots
            }
        }
    }

    private func calculateBolusDots(fullSize: CGSize) {
        calculationQueue.async {
            let dots = data.useInsulinBars ? insulinBarEntries(fullSize: fullSize) :
                (data.boluses.map { value -> DotInfo in
                    let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970, fullSize: fullSize)
                    let size = Config.bolusSize + CGFloat(value.amount ?? 0) * Config.bolusScale
                    let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                    return DotInfo(rect: rect, value: value.amount ?? 0)
                })

            let path = Path { path in
                for dot in dots {
                    path.addEllipse(in: dot.rect)
                }
            }

            DispatchQueue.main.async {
                bolusDots = dots
                bolusPath = path
            }
        }
    }

    private func calculateCarbsDots(fullSize: CGSize) {
        calculationQueue.async {
            let realCarbs = data.carbs.filter { !($0.isFPU ?? false) }
            let dots = realCarbs.map { value -> DotInfo in
                let center = timeToInterpolatedPoint(
                    value.actualDate != nil ? (value.actualDate ?? Date()).timeIntervalSince1970 : value.createdAt
                        .timeIntervalSince1970,
                    fullSize: fullSize
                )
                let size = Config.carbsSize + CGFloat(value.carbs) * Config.carbsScale
                let rect = CGRect(
                    x: center.x - size / 2,
                    y: (center.y - size / 2) + Config.carbOffset + (size / 2),
                    width: size,
                    height: size // + CGFloat(value.carbs) * Config.carbsScale
                )
                return DotInfo(rect: rect, value: value.carbs)
            }

            let path = Path { path in
                for dot in dots {
                    path.addEllipse(in: dot.rect)
                }
            }

            DispatchQueue.main.async {
                carbsDots = dots
                carbsPath = path
            }
        }
    }

    private func calculateFPUsDots(fullSize: CGSize) {
        calculationQueue.async {
            let fpus = data.carbs.filter { $0.isFPU ?? false }
            let dots = fpus.map { value -> DotInfo in
                let center = timeToInterpolatedPoint(
                    value.actualDate != nil ? (value.actualDate ?? Date()).timeIntervalSince1970 : value.createdAt
                        .timeIntervalSince1970,
                    fullSize: fullSize
                )
                let size = Config.fpuSize + CGFloat(value.carbs) * Config.fpuScale
                let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                return DotInfo(rect: rect, value: value.carbs)
            }

            let path = Path { path in
                for dot in dots {
                    path.addEllipse(in: dot.rect)
                }
            }

            DispatchQueue.main.async {
                fpuDots = dots
                fpuPath = path
            }
        }
    }

    private func calculatePredictionDots(fullSize: CGSize, type: PredictionType) {
        calculationQueue.async {
            let values: [Int] = { () -> [Int] in
                switch type {
                case .iob:
                    return data.suggestion?.predictions?.iob ?? []
                case .cob:
                    return data.suggestion?.predictions?.cob ?? []
                case .zt:
                    return data.suggestion?.predictions?.zt ?? []
                case .uam:
                    return data.suggestion?.predictions?.uam ?? []
                }
            }()

            var index = 0
            let dots = values.map { value -> CGRect in
                let position = predictionToCoordinate(value, fullSize: fullSize, index: index)
                index += 1
                return CGRect(x: position.x - 2, y: position.y - 2, width: 3, height: 3)
            }
            DispatchQueue.main.async {
                predictionDots[type] = dots
            }
        }
    }

    private func calculateBasalPoints(fullSize: CGSize) {
        calculationQueue.async {
            self.cachedMaxBasalRate = nil
            let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
            let firstTempTime = (data.tempBasals.first?.timestamp ?? Date()).timeIntervalSince1970
            var lastTimeEnd = firstTempTime
            let firstRegularBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: firstTempTime,
                fullSize: fullSize,
                autotuned: false
            )
            let tempBasalPoints = firstRegularBasalPoints + data.tempBasals.chunks(ofCount: 2).map { chunk -> [CGPoint] in
                let chunk = Array(chunk)
                guard chunk.count == 2, chunk[0].type == .tempBasal, chunk[1].type == .tempBasalDuration else { return [] }
                let timeBegin = chunk[0].timestamp.timeIntervalSince1970
                let timeEnd = timeBegin + (chunk[1].durationMin ?? 0).minutes.timeInterval
                let rateCost = Config.basalHeight / CGFloat(maxBasalRate())
                let x0 = timeToXCoordinate(timeBegin, fullSize: fullSize)
                let y0 = Config.basalHeight - CGFloat(chunk[0].rate ?? 0) * rateCost
                let regularPoints = findRegularBasalPoints(
                    timeBegin: lastTimeEnd,
                    timeEnd: timeBegin,
                    fullSize: fullSize,
                    autotuned: false
                )
                lastTimeEnd = timeEnd
                return regularPoints + [CGPoint(x: x0, y: y0)]
            }.flatMap { $0 }
            let tempBasalPath = Path { path in
                var yPoint: CGFloat = Config.basalHeight
                path.move(to: CGPoint(x: 0, y: yPoint))

                for point in tempBasalPoints {
                    path.addLine(to: CGPoint(x: point.x, y: yPoint))
                    path.addLine(to: point)
                    yPoint = point.y
                }
                let lastPoint = lastBasalPoint(fullSize: fullSize)
                path.addLine(to: CGPoint(x: lastPoint.x, y: yPoint))
                path.addLine(to: CGPoint(x: lastPoint.x, y: Config.basalHeight))
                path.addLine(to: CGPoint(x: 0, y: Config.basalHeight))
            }
            let adjustForOptionalExtraHours = data.screenHours > 12 ? data.screenHours - 12 : 0
            let endDateTime = dayAgoTime + min(max(Int(data.screenHours - adjustForOptionalExtraHours), 12), 24).hours
                .timeInterval + min(max(Int(data.screenHours - adjustForOptionalExtraHours), 12), 24).hours
                .timeInterval
            let autotunedBasalPoints = findRegularBasalPoints(
                timeBegin: dayAgoTime,
                timeEnd: endDateTime,
                fullSize: fullSize,
                autotuned: true
            )

            let autotunedBasalPath = Path { path in
                var yPoint: CGFloat = Config.basalHeight
                path.move(to: CGPoint(x: -50, y: yPoint))

                for point in autotunedBasalPoints {
                    path.addLine(to: CGPoint(x: point.x, y: yPoint))
                    path.addLine(to: point)
                    yPoint = point.y
                }
                path.addLine(to: CGPoint(x: timeToXCoordinate(endDateTime, fullSize: fullSize), y: yPoint))
            }

            DispatchQueue.main.async {
                self.tempBasalPath = tempBasalPath
                self.regularBasalPath = autotunedBasalPath
            }
        }
    }

    private func calculateSuspensions(fullSize: CGSize) {
        calculationQueue.async {
            var rects = data.suspensions.windows(ofCount: 2).map { window -> CGRect? in
                let window = Array(window)
                guard window[0].type == .pumpSuspend, window[1].type == .pumpResume else { return nil }
                let x0 = self.timeToXCoordinate(window[0].timestamp.timeIntervalSince1970, fullSize: fullSize)
                let x1 = self.timeToXCoordinate(window[1].timestamp.timeIntervalSince1970, fullSize: fullSize)
                return CGRect(x: x0, y: 0, width: x1 - x0, height: Config.basalHeight * 0.7)
            }

            let firstRec = self.data.suspensions.first.flatMap { event -> CGRect? in
                guard event.type == .pumpResume else { return nil }
                let tbrTime = self.data.tempBasals.last { $0.timestamp < event.timestamp }
                    .map { $0.timestamp.timeIntervalSince1970 + TimeInterval($0.durationMin ?? 0) * 60 } ?? Date()
                    .addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970

                let x0 = self.timeToXCoordinate(tbrTime, fullSize: fullSize)
                let x1 = self.timeToXCoordinate(event.timestamp.timeIntervalSince1970, fullSize: fullSize)
                return CGRect(
                    x: x0,
                    y: 0,
                    width: x1 - x0,
                    height: Config.basalHeight * 0.7
                )
            }

            let lastRec = self.data.suspensions.last.flatMap { event -> CGRect? in
                guard event.type == .pumpSuspend else { return nil }
                let tbrTimeX = self.data.tempBasals.first { $0.timestamp > event.timestamp }
                    .map { self.timeToXCoordinate($0.timestamp.timeIntervalSince1970, fullSize: fullSize) }
                let x0 = self.timeToXCoordinate(event.timestamp.timeIntervalSince1970, fullSize: fullSize)

                let x1 = tbrTimeX ?? self.fullGlucoseWidth(viewWidth: fullSize.width) + self
                    .additionalWidth(viewWidth: fullSize.width)

                return CGRect(x: x0, y: 0, width: x1 - x0, height: Config.basalHeight * 0.7)
            }
            rects.append(firstRec)
            rects.append(lastRec)

            let path = Path { path in
                path.addRects(rects.compactMap { $0 })
            }

            DispatchQueue.main.async {
                suspensionsPath = path
            }
        }
    }

    private func maxBasalRate() -> Decimal {
        if let cached = cachedMaxBasalRate {
            return cached
        }

        let maxRegularBasalRate = max(
            data.basalProfile.map(\.rate).max() ?? data.maxBasal,
            data.autotunedBasalProfile.map(\.rate).max() ?? data.maxBasal
        )

        var maxTempBasalRate = data.tempBasals.compactMap(\.rate).max() ?? maxRegularBasalRate
        if maxTempBasalRate == 0 {
            maxTempBasalRate = maxRegularBasalRate
        }

        cachedMaxBasalRate = max(maxTempBasalRate, maxRegularBasalRate)
        return cachedMaxBasalRate ?? data.maxBasal
    }

    private func calculateTempTargetsRects(fullSize: CGSize) {
        calculationQueue.async {
            var rects = data.tempTargets.map { tempTarget -> CGRect in
                let x0 = timeToXCoordinate(tempTarget.createdAt.timeIntervalSince1970, fullSize: fullSize)
                let y0 = glucoseToYCoordinate(Int(tempTarget.targetTop ?? 0), fullSize: fullSize)
                let x1 = timeToXCoordinate(
                    tempTarget.createdAt.timeIntervalSince1970 + Int(tempTarget.duration).minutes.timeInterval,
                    fullSize: fullSize
                )
                let y1 = glucoseToYCoordinate(Int(tempTarget.targetBottom ?? 0), fullSize: fullSize)
                return CGRect(
                    x: x0,
                    y: y0 - 3,
                    width: x1 - x0,
                    height: y1 - y0 + 6
                )
            }
            if rects.count > 1 {
                rects = rects.reduce([]) { result, rect -> [CGRect] in
                    guard var last = result.last else { return [rect] }
                    if last.origin.x + last.width > rect.origin.x {
                        last.size.width = rect.origin.x - last.origin.x
                    }
                    var res = Array(result.dropLast())
                    res.append(contentsOf: [last, rect])
                    return res
                }
            }
            let path = Path { path in
                path.addRects(rects)
            }
            DispatchQueue.main.async {
                tempTargetsPath = path
            }
        }
    }

    private func calculateOverridesRects(fullSize: CGSize) {
        calculationQueue.async {
            let latest = OverrideStorage().fetchLatestOverride().first
            let rects = data.overrideHistory.compactMap { each -> CGRect in
                let duration = each.duration
                let xStart = timeToXCoordinate(each.date!.timeIntervalSince1970, fullSize: fullSize)
                let xEnd = timeToXCoordinate(
                    each.date!.addingTimeInterval(Int(duration).minutes.timeInterval).timeIntervalSince1970,
                    fullSize: fullSize
                )
                let y = glucoseToYCoordinate(Int(each.target), fullSize: fullSize)
                return CGRect(
                    x: xStart,
                    y: y - 3,
                    width: xEnd - xStart,
                    height: 6
                )
            }
            // Display active Override
            if let last = latest, last.enabled {
                var old = Array(rects)
                let duration = Double(last.duration ?? 0)
                // Looks better when target isn't == 0 in Home View Main Chart
                let targetRaw = last.target ?? 0
                let target = Int(targetRaw) < 6 ? 6 : targetRaw

                if duration > 0 {
                    let x1 = timeToXCoordinate((latest?.date ?? Date.now).timeIntervalSince1970, fullSize: fullSize)
                    let plusNow = (last.date ?? Date.now).addingTimeInterval(Int(latest?.duration ?? 0).minutes.timeInterval)
                    let x2 = timeToXCoordinate(plusNow.timeIntervalSince1970, fullSize: fullSize)
                    let oneMore = CGRect(
                        x: x1,
                        y: glucoseToYCoordinate(Int(target), fullSize: fullSize) - 3,
                        width: x2 - x1,
                        height: 6
                    )
                    old.append(oneMore)
                    let path = Path { path in
                        path.addRects(old)
                    }
                    return DispatchQueue.main.async {
                        overridesPath = path
                    }
                } else {
                    let x1 = timeToXCoordinate((last.date ?? Date.now).timeIntervalSince1970, fullSize: fullSize)
                    let x2 = timeToXCoordinate(Date.now.timeIntervalSince1970, fullSize: fullSize)
                    let oneMore = CGRect(
                        x: x1,
                        y: glucoseToYCoordinate(Int(target), fullSize: fullSize) - 3,
                        width: x2 - x1 + additionalWidth(viewWidth: fullSize.width),
                        height: 6
                    )
                    old.append(oneMore)
                    let path = Path { path in
                        path.addRects(old)
                    }
                    return DispatchQueue.main.async {
                        overridesPath = path
                    }
                }
            }
            let path = Path { path in
                path.addRects(rects)
            }
            DispatchQueue.main.async {
                overridesPath = path
            }
        }
    }

    private func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval,
        fullSize: CGSize,
        autotuned: Bool
    ) -> [CGPoint] {
        guard timeBegin < timeEnd else {
            return []
        }
        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: beginDate)

        let profile = autotuned ? data.autotunedBasalProfile : data.basalProfile

        let basalNormalized = profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        } + profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 1.days.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        } + profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 2.days.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        }

        let basalTruncatedPoints = basalNormalized.windows(ofCount: 2)
            .compactMap { window -> CGPoint? in
                let window = Array(window)
                if window[0].time < timeBegin, window[1].time < timeBegin {
                    return nil
                }

                let rateCost = Config.basalHeight / CGFloat(maxBasalRate())
                if window[0].time < timeBegin, window[1].time >= timeBegin {
                    let x = timeToXCoordinate(timeBegin, fullSize: fullSize)
                    let y = Config.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                if window[0].time >= timeBegin, window[0].time < timeEnd {
                    let x = timeToXCoordinate(window[0].time, fullSize: fullSize)
                    let y = Config.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                return nil
            }
        return basalTruncatedPoints
    }

    private func lastBasalPoint(fullSize: CGSize) -> CGPoint {
        let lastBasal = Array(data.tempBasals.suffix(2))
        guard lastBasal.count == 2 else {
            return CGPoint(x: timeToXCoordinate(Date().timeIntervalSince1970, fullSize: fullSize), y: Config.basalHeight)
        }
        let endBasalTime = lastBasal[0].timestamp.timeIntervalSince1970 + (lastBasal[1].durationMin?.minutes.timeInterval ?? 0)
        let rateCost = Config.basalHeight / CGFloat(maxBasalRate())
        let x = timeToXCoordinate(endBasalTime, fullSize: fullSize)
        let y = Config.basalHeight - CGFloat(lastBasal[0].rate ?? 0) * rateCost
        return CGPoint(x: x, y: y)
    }

    private func fullGlucoseWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(data.hours) / CGFloat(min(max(data.screenHours, 2), 24))
    }

    private func additionalWidth(viewWidth: CGFloat) -> CGFloat {
        guard let predictions = data.suggestion?.predictions,
              let deliveredAt = data.suggestion?.deliverAt,
              let last = data.glucose.last
        else {
            return Config.minAdditionalWidth
        }

        let iob = predictions.iob?.count ?? 0
        let zt = predictions.zt?.count ?? 0
        let cob = predictions.cob?.count ?? 0
        let uam = predictions.uam?.count ?? 0
        let max = [iob, zt, cob, uam].max() ?? 0

        let lastDeltaTime = last.dateString.timeIntervalSince(deliveredAt)

        let additionalTime = CGFloat(TimeInterval(max) * 5.minutes.timeInterval - lastDeltaTime)
        let oneSecondWidth = oneSecondStep(viewWidth: viewWidth)

        return Swift.min(Swift.max(additionalTime * oneSecondWidth, Config.minAdditionalWidth), 275)
    }

    private func oneSecondStep(viewWidth: CGFloat) -> CGFloat {
        viewWidth / (CGFloat(min(max(data.screenHours, 2), 24)) * CGFloat(1.hours.timeInterval))
    }

    private func maxPredValue() -> Int? {
        [
            data.suggestion?.predictions?.cob ?? [],
            data.suggestion?.predictions?.iob ?? [],
            data.suggestion?.predictions?.zt ?? [],
            data.suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .max()
    }

    private func minPredValue() -> Int? {
        [
            data.suggestion?.predictions?.cob ?? [],
            data.suggestion?.predictions?.iob ?? [],
            data.suggestion?.predictions?.zt ?? [],
            data.suggestion?.predictions?.uam ?? []
        ]
        .flatMap { $0 }
        .min()
    }

    private func maxTargetValue() -> Int? {
        data.tempTargets.map { $0.targetTop ?? 0 }.filter { $0 > 0 }.max().map(Int.init)
    }

    private func minTargetValue() -> Int? {
        data.tempTargets.map { $0.targetBottom ?? 0 }.filter { $0 > 0 }.min().map(Int.init)
    }

    private func glucoseToCoordinate(_ glucoseEntry: BloodGlucose, fullSize: CGSize) -> CGPoint {
        let x = timeToXCoordinate(glucoseEntry.dateString.timeIntervalSince1970, fullSize: fullSize)
        let y = glucoseToYCoordinate(glucoseEntry.glucose ?? 0, fullSize: fullSize)

        return CGPoint(x: x, y: y)
    }

    private func UnSmoothedGlucoseToCoordinate(_ glucoseEntry: BloodGlucose, fullSize: CGSize) -> CGPoint {
        let x = timeToXCoordinate(glucoseEntry.dateString.timeIntervalSince1970, fullSize: fullSize)
        let glucoseValue: Decimal = glucoseEntry.unfiltered ?? Decimal(glucoseEntry.glucose ?? 0)
        let y = glucoseToYCoordinate(Int(glucoseValue), fullSize: fullSize)

        return CGPoint(x: x, y: y)
    }

    private func predictionToCoordinate(_ pred: Int, fullSize: CGSize, index: Int) -> CGPoint {
        guard let deliveredAt = data.suggestion?.deliverAt else {
            return .zero
        }

        let predTime = deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes.timeInterval
        let x = timeToXCoordinate(predTime, fullSize: fullSize)
        let y = glucoseToYCoordinate(pred, fullSize: fullSize)

        return CGPoint(x: x, y: y)
    }

    private func timeToXCoordinate(_ time: TimeInterval, fullSize: CGSize) -> CGFloat {
        let xOffset = -Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        let stepXFraction = fullGlucoseWidth(viewWidth: fullSize.width) / CGFloat(data.hours.hours.timeInterval)
        let x = CGFloat(time + xOffset) * stepXFraction
        return x
    }

    private func glucoseToYCoordinate(_ glucoseValue: Int, fullSize: CGSize) -> CGFloat {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let (minValue, maxValue) = minMaxYValues()
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let y = fullSize.height - CGFloat(glucoseValue) * stepYFraction + yOffset - bottomYPadding
        return y
    }

    private func timeToInterpolatedPoint(_ time: TimeInterval, fullSize: CGSize) -> CGPoint {
        var nextIndex = 0
        for (index, value) in data.glucose.enumerated() {
            if value.dateString.timeIntervalSince1970 > time {
                nextIndex = index
                break
            }
        }
        let x = timeToXCoordinate(time, fullSize: fullSize)

        guard nextIndex > 0 else {
            let lastY = glucoseToYCoordinate(data.glucose.last?.glucose ?? 0, fullSize: fullSize)
            return CGPoint(x: x, y: lastY)
        }

        let prevX = timeToXCoordinate(data.glucose[nextIndex - 1].dateString.timeIntervalSince1970, fullSize: fullSize)
        let prevY = glucoseToYCoordinate(data.glucose[nextIndex - 1].glucose ?? 0, fullSize: fullSize)
        let nextX = timeToXCoordinate(data.glucose[nextIndex].dateString.timeIntervalSince1970, fullSize: fullSize)
        let nextY = glucoseToYCoordinate(data.glucose[nextIndex].glucose ?? 0, fullSize: fullSize)
        let delta = nextX - prevX
        let fraction = (x - prevX) / delta

        return pointInLine(CGPoint(x: prevX, y: prevY), CGPoint(x: nextX, y: nextY), fraction)
    }

    private func minMaxYValues() -> (min: Int, max: Int) {
        var maxValue = data.glucose.compactMap(\.glucose).max() ?? Config.maxGlucose
        if let maxPredValue = maxPredValue() {
            maxValue = max(maxValue, maxPredValue)
        }
        if let maxTargetValue = maxTargetValue() {
            maxValue = max(maxValue, maxTargetValue)
        }
        var minValue = data.glucose.compactMap(\.glucose).min() ?? Config.minGlucose
        if let minPredValue = minPredValue() {
            minValue = min(minValue, minPredValue)
        }
        if let minTargetValue = minTargetValue() {
            minValue = min(minValue, minTargetValue)
        }

        if minValue == maxValue {
            minValue = Config.minGlucose
            maxValue = Config.maxGlucose
        }
        // fix the grah y-axis as long as the min and max BG values are within set borders
        if minValue > Config.minGlucose {
            minValue = Config.minGlucose
        }

        return (min: minValue, max: maxValue)
    }

    private func getGlucoseYRange(fullSize: CGSize) -> GlucoseYRange {
        let topYPaddint = Config.topYPadding + Config.basalHeight
        let bottomYPadding = Config.bottomYPadding
        let (minValue, maxValue) = minMaxYValues()
        let stepYFraction = (fullSize.height - topYPaddint - bottomYPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let maxY = fullSize.height - CGFloat(minValue) * stepYFraction + yOffset - bottomYPadding
        let minY = fullSize.height - CGFloat(maxValue) * stepYFraction + yOffset - bottomYPadding
        return (minValue: minValue, minY: minY, maxValue: maxValue, maxY: maxY)
    }

    private func firstHourDate() -> Date {
        let firstDate = Date().addingTimeInterval(-1.days.timeInterval)
        return firstDate.dateTruncated(from: .minute)!
    }

    private func firstHourPosition(viewWidth: CGFloat) -> CGFloat {
        let firstDate = Date().addingTimeInterval(-1.days.timeInterval)
        let firstHour = firstHourDate()

        let lastDeltaTime = firstHour.timeIntervalSince(firstDate)
        let oneSecondWidth = oneSecondStep(viewWidth: viewWidth)
        return oneSecondWidth * CGFloat(lastDeltaTime)
    }

    // An InsulinBarMark of sorts
    private func insulinBar() -> Path {
        Path { path in
            for dot in bolusDots {
                let rect = dot.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY + Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY - Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - Config.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + Config.pointSizeHeight))
            }
        }
    }

    private func insulinBarEntries(fullSize: CGSize) -> [DotInfo] {
        data.boluses.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970, fullSize: fullSize)
            let height = bolusHeight(amount: value.amount ?? 0)
            let rect = CGRect(
                x: center.x,
                y: center.y - height - Config.insulinOffset,
                width: bolusWidth(value: value.amount ?? 0),
                height: height
            )
            return DotInfo(rect: rect, value: value.amount ?? 0)
        }
    }

    private func bolusHeight(amount: Decimal) -> CGFloat {
        let height = (amount / data.maxBolusValue) * Config.bolusHeight
        return CGFloat(height)
    }

    private func bolusWidth(value: Decimal) -> CGFloat {
        switch data.screenHours {
        case 12:
            return value < data.minimumSMB ? 2.5 : 3
        case 24:
            return value < data.minimumSMB ? 1.5 : 2
        default:
            return value < data.minimumSMB ? 3.5 : 4
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
