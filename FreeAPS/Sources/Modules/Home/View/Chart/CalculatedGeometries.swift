import Foundation
import SwiftUI

class CalculatedGeometries {
    let fullSize: CGSize
    private let data: ChartModel

    private(set) var glucose: [BloodGlucose]
    private(set) var boluses: [PumpHistoryEvent] = []
    private(set) var realCarbs: [CarbsEntry] = []
    private(set) var fpus: [CarbsEntry] = []

    private(set) var glucoseDots: [(rect: CGRect, glucose: Int?)] = []
    private(set) var activityDots: [CGPoint] = []
    private(set) var activityZeroPointY: CGFloat?
    private(set) var cobDots: [(CGPoint, IOBData)] = []
    private(set) var cobZeroPointY: CGFloat?
    private(set) var manualGlucoseDots: [CGRect] = []
    private(set) var announcementDots: [AnnouncementDot] = []
    private(set) var announcementPath = Path()
    private(set) var manualGlucoseDotsCenter: [CGRect] = []
    private(set) var unSmoothedGlucoseDots: [CGRect] = []
    private(set) var predictionDotsIOB: [CGRect] = []
    private(set) var predictionDotsCOB: [CGRect] = []
    private(set) var predictionDotsZT: [CGRect] = []
    private(set) var predictionDotsUAM: [CGRect] = []
    private(set) var bolusDots: [DotInfo] = []
    private(set) var bolusPath = Path()
    private(set) var tempBasalPath = Path()
    private(set) var regularBasalPath = Path()
    private(set) var tempTargetsPath = Path()
    private(set) var overridesPath = Path()
    private(set) var suspensionsPath = Path()
    private(set) var carbsDots: [DotInfo] = []
    private(set) var carbsPath = Path()
    private(set) var fpuDots: [DotInfo] = []
    private(set) var fpuPath = Path()
    private(set) var glucoseYRange: GlucoseYRange = (0, 0, 0, 0)
    private(set) var offset: CGFloat = 0
    private(set) var cachedMaxBasalRate: Decimal?
    private(set) var activityChartMinMax: (Double, Double) = (0, 1)
    private(set) var cobChartMinMax: (Double, Double) = (0, 1)
    private(set) var peakActivity_1unit: Double = 0.0
    private(set) var peakActivity_1unit_y: CGFloat = 0.0
    private(set) var peakActivity_maxBolus: Double = 0.0
    private(set) var peakActivity_maxBolus_y: CGFloat = 0.0
    private(set) var peakActivity_maxIOB: Double = 0.0
    private(set) var peakActivity_maxIOB_y: CGFloat = 0.0
    private(set) var maxActivityInData: Decimal?
    private(set) var horizontalGrid: [(CGFloat, Int)] = []
    private(set) var lowThresholdLine: (CGFloat, Int)?
    private(set) var highThresholdLine: (CGFloat, Int)?
    private(set) var glucosePeaks: [GlucosePeak] = []

    private(set) var firstHourDate = Date()
    private(set) var oneSecondWidth: CGFloat = 0
    private(set) var additionalWidth: CGFloat = 0
    private(set) var fullGlucoseWidth: CGFloat = 0
    private(set) var firstHourPosition: CGFloat = 0
    private(set) var currentTimeX: CGFloat = 0

    private var glucoseMinValue: Int = 0
    private var glucoseMaxValue: Int = 0

    private(set) var bolusFont = Font.custom("BolusDotFont", fixedSize: 11)
    private var bolusUIFont = UIFont.systemFont(ofSize: 11)

    private(set) var peaksFont = Font.custom("BolusDotFont", fixedSize: 13)
    private var peaksUIFont = UIFont.systemFont(ofSize: 13)

    private let bolusFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }()

    private let carbsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private let dotGlucoseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }()

    private let mmolDotGlucoseFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.decimalSeparator = "."
        return formatter
    }()

    init(
        fullSize: CGSize,
        data: ChartModel
    ) {
        let started = Date.now

        self.fullSize = fullSize
        self.data = data

        // these need to be sorted by date ascending (for the incremental matching against glucose values)
        glucose = data.glucose.sorted {
            $0.dateString < $1.dateString
        }
        boluses = data.boluses.sorted {
            $0.timestamp < $1.timestamp
        }
        realCarbs = data.carbs
            .filter { !($0.isFPU ?? false) }
            .sorted {
                ($0.actualDate ?? .distantPast) < ($1.actualDate ?? .distantPast)
            }
        fpus = data.carbs
            .filter { $0.isFPU ?? false }
            .sorted {
                ($0.actualDate ?? .distantPast) < ($1.actualDate ?? .distantPast)
            }

        let (bolusFont, bolusUIFont) = getBolusFont()
        self.bolusFont = bolusFont
        self.bolusUIFont = bolusUIFont

        let (peaksFont, peaksUIFont) = getPeaksFont()
        self.peaksFont = peaksFont
        self.peaksUIFont = peaksUIFont

        firstHourDate = calculateFirstHourDate()
        oneSecondWidth = calculateOneSecondStep()
        additionalWidth = calculateAdditionalWidth()
        fullGlucoseWidth = calculateFullGlucoseWidth()
        firstHourPosition = calculateFirstHourPosition()

        let (glucoseMinValue, glucoseMaxValue) = glucoseMinMaxYValues()
        self.glucoseMinValue = glucoseMinValue
        self.glucoseMaxValue = glucoseMaxValue

        currentTimeX = timeToXCoordinate(Date.now.timeIntervalSince1970)

        peakActivity_1unit = peakInsulinActivity(forBolus: 1.0)
        peakActivity_maxBolus = peakInsulinActivity(forBolus: Double(data.maxBolus))
        peakActivity_maxIOB = peakInsulinActivity(forBolus: Double(data.maxIOB))
        maxActivityInData = data.activity.map { e in e.activity }.max()

        activityChartMinMax = calculateActivityChartMinMax()
        cobChartMinMax = calculateCobChartMinMax()

        peakActivity_1unit_y = activityToYCoordinate(Decimal(peakActivity_1unit))
        peakActivity_maxBolus_y = activityToYCoordinate(Decimal(peakActivity_maxBolus))
        peakActivity_maxIOB_y = activityToYCoordinate(Decimal(peakActivity_maxIOB))

        predictionDotsIOB = calculatePredictionDots(type: .iob)
        predictionDotsCOB = calculatePredictionDots(type: .cob)
        predictionDotsZT = calculatePredictionDots(type: .zt)
        predictionDotsUAM = calculatePredictionDots(type: .uam)

        glucoseYRange = getGlucoseYRange()

        glucoseDots = calculateGlucoseDots()

        activityDots = calculateActivityDots()
        activityZeroPointY = activityToCoordinate(date: Date(), activity: 0).y // only y-coordinate matters

        cobDots = calculateCobDots()
        cobZeroPointY = cobToCoordinate(date: Date(), cob: 0).y // only y-coordinate matters

        manualGlucoseDots = calculateManualGlucoseDots()

        manualGlucoseDotsCenter = calculateManualGlucoseDotsCenter()

        announcementDots = calculateAnnouncementDots()
        announcementPath = makeAnnouncementPath()

        unSmoothedGlucoseDots = calculateUnSmoothedGlucoseDots()

        bolusDots = calculateBolusDots()
        bolusPath = data.useInsulinBars ? insulinBarsPath() : insulinCirclesPath()

        carbsDots = calculateCarbsDots()
        carbsPath = data.useCarbBars ? carbsBarsPath(carbsDots) : carbsCirclesPath(carbsDots)

        fpuDots = calculateFPUsDots()
        fpuPath = data.useCarbBars ? carbsBarsPath(fpuDots) : carbsCirclesPath(fpuDots)

        tempTargetsPath = calculateTempTargetsRects()

        overridesPath = calculateOverridesRects()

        let (tempBasalPath, regularBasalPath) = calculateBasalPoints()

        self.tempBasalPath = tempBasalPath
        self.regularBasalPath = regularBasalPath

        suspensionsPath = calculateSuspensions()

        let (horizontalGrid, lowThresholdLine, highThresholdLine) = calculateHorizontalLines()

        self.horizontalGrid = horizontalGrid
        self.lowThresholdLine = lowThresholdLine
        self.highThresholdLine = highThresholdLine

        if data.chartGlucosePeaks {
            glucosePeaks = calculateGlucosePeaks()
        }

        let ended = Date.now

        // TODO: remove this
        print(
            "main chart update: \(ended.timeIntervalSince(started) * 1000) milliseconds"
        )
    }

    private func roundGlucoseToNearestNiceValue(_ value: Int) -> Int {
        if data.units == .mgdL {
            return Int((Double(value) / 50.0).rounded() * 50.0)
        } else {
            // Convert to mmol/L
            let mmol = Decimal(value) * GlucoseUnits.exchangeRate
            let roundedMmol = mmol.rounded(to: 0)
            // Convert back to mg/dL
            let roundedMgdl = roundedMmol / GlucoseUnits.exchangeRate
            return Int(NSDecimalNumber(decimal: roundedMgdl).doubleValue.rounded())
        }
    }

    private func glucoseLines(from: Int, through: Int) -> StrideThrough<Int> {
        let step: Int =
            data.units == .mgdL ?
            Int(NSDecimalNumber(decimal: 3.0 / GlucoseUnits.exchangeRate).doubleValue) // 3 mmol/L
            : 50 // 50 mg/dl

        return stride(from: from + step, through: through - step, by: step)
    }

    private func calculateHorizontalLines() -> ([(CGFloat, Int)], (CGFloat, Int), (CGFloat, Int)) {
        var lines: [(CGFloat, Int)] = []

        let highGlucoseInt = Int(NSDecimalNumber(decimal: data.highGlucose).doubleValue.rounded())
        let lowGlucoseInt = Int(NSDecimalNumber(decimal: data.lowGlucose).doubleValue.rounded())

        let lowLine = (glucoseToYCoordinate(lowGlucoseInt), lowGlucoseInt)
        let highLine = (glucoseToYCoordinate(highGlucoseInt), highGlucoseInt)

        if let glucoseMin = glucose.compactMap(\.glucose).min(),
           let glucoseMax = glucose.compactMap(\.glucose).max()
        {
            if glucoseMin < lowGlucoseInt {
                lines.append(lowLine)
                if glucoseMin < lowGlucoseInt - 18 {
                    lines.append((glucoseToYCoordinate(glucoseMin), glucoseMin))
                }
            } else {
                lines.append((glucoseToYCoordinate(glucoseMin), glucoseMin))
            }

            if glucoseMax > highGlucoseInt {
                lines.append(highLine)
                if glucoseMax > highGlucoseInt + 18 {
                    lines.append((glucoseToYCoordinate(glucoseMax), glucoseMax))
                    for g in glucoseLines(from: highGlucoseInt, through: glucoseMax) {
                        let nice = roundGlucoseToNearestNiceValue(g)
                        lines.append((glucoseToYCoordinate(nice), nice))
                    }
                }
            } else {
                lines.append((glucoseToYCoordinate(glucoseMax), glucoseMax))
            }
        }

        return (
            lines,
            lowLine,
            highLine
        )
    }

    private func calculateGlucosePeaks() -> [GlucosePeak] {
        let (maxima, minima) = PeakPicker.pick(data: glucose, windowHours: Double(data.screenHours) / 2.0)

        // y, x-start, x-end, glucose value
        var glucosePeaks: [GlucosePeak] = []

        let formatter = data.units == .mmolL ? mmolDotGlucoseFormatter : dotGlucoseFormatter

        let peakHorizontalPadding = ChartConfig.peakHorizontalPadding
        let peakVerticalPadding = ChartConfig.peakVerticalPadding
        let peakMargin = ChartConfig.peakMargin

        for peak in maxima {
            if let glucose = peak.glucose, glucose != 0 {
                let point = glucoseToCoordinate(peak)

                let value = Double(glucose) *
                    (data.units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

                if let string = formatter.string(from: value as NSNumber) {
                    var textSize = textSize(text: string, font: peaksUIFont)
                    textSize.width += peakHorizontalPadding * 2 + peakMargin * 2
                    textSize.height += peakVerticalPadding * 2 + peakMargin * 2
                    let textRect = CGRect(
                        origin: CGPoint(
                            x: point.x - textSize.width / 2,
                            y: point.y - textSize.height / 2 - 18
                        ),
                        size: textSize
                    )

                    if let placedRect = positionPeak(rect: textRect, .max) {
                        glucosePeaks.append(
                            GlucosePeak(
                                xStart: point.x,
                                yStart: point.y,
                                glucose: glucose,
                                text: string,
                                textRect: placedRect,
                                type: .max
                            )
                        )
                    }
                }
            }
        }

        for peak in minima {
            if let glucose = peak.glucose, glucose != 0 {
                let point = glucoseToCoordinate(peak)

                let value = Double(glucose) *
                    (data.units == .mmolL ? Double(GlucoseUnits.exchangeRate) : 1)

                if let string = formatter.string(from: value as NSNumber) {
                    var textSize = textSize(text: string, font: peaksUIFont)
                    textSize.width += peakHorizontalPadding * 2 + peakMargin * 2
                    textSize.height += peakVerticalPadding * 2 + peakMargin * 2
                    let textRect = CGRect(
                        origin: CGPoint(
                            x: point.x - textSize.width / 2,
                            y: point.y - textSize.height / 2 + 18
                        ),
                        size: textSize
                    )

                    if let updatedRect = positionPeak(rect: textRect, .min) {
                        glucosePeaks.append(
                            GlucosePeak(
                                xStart: point.x,
                                yStart: point.y,
                                glucose: glucose,
                                text: string,
                                textRect: updatedRect,
                                type: .min
                            )
                        )
                    }
                }
            }
        }

        return glucosePeaks
    }

    private func positionPeak(rect: CGRect, _ type: ExtremumType) -> CGRect? {
        let maxDistance: CGFloat = 80.0
        if type == .max {
            return bolusDots.placeLabelCenter(
                desiredRect: rect,
                verticalSide: .above,
                maxDistance: maxDistance
            )
        } else {
            return carbsDots.placeLabelCenter(
                desiredRect: rect,
                verticalSide: .below,
                maxDistance: maxDistance,
            )
        }
    }

    private func calculateActivityDots() -> [CGPoint] {
        data.activity.map { value -> CGPoint in
            activityToCoordinate(date: value.time, activity: value.activity)
        }
    }

    private func calculateCobDots() -> [(CGPoint, IOBData)] {
        data.cob.map { value -> (CGPoint, IOBData) in
            (cobToCoordinate(date: value.date, cob: value.cob), value)
        }
    }

    private func calculateGlucoseDots() -> [(rect: CGRect, glucose: Int?)] {
        let dots = glucose.map { value -> (CGRect, Int?) in
            let position = glucoseToCoordinate(value)
            return (
                CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: ChartConfig.glucoseSize),
                value.glucose
            )
        }
        return dots
    }

    private func calculateManualGlucoseDots() -> [CGRect] {
        data.isManual.map { value -> CGRect in
            let position = glucoseToCoordinate(value)
            return CGRect(x: position.x - 6, y: position.y - 6, width: 14, height: 14)
        }
    }

    private func calculateManualGlucoseDotsCenter() -> [CGRect] {
        data.isManual.map { value -> CGRect in
            let position = glucoseToCoordinate(value)
            return CGRect(x: position.x - 4, y: position.y - 4, width: 10, height: 10)
        }
    }

    private func calculateAnnouncementDots() -> [AnnouncementDot] {
        let dots = data.announcement.map { value -> AnnouncementDot in
            let center = timeToInterpolatedPoint(value.createdAt.timeIntervalSince1970)
            let size = ChartConfig.announcementSize * ChartConfig.announcementScale
            let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let note = value.notes
            return AnnouncementDot(rect: rect, value: 10, note: note)
        }
        return dots
    }

    private func makeAnnouncementPath() -> Path {
        Path { path in
            for dot in announcementDots {
                path.addEllipse(in: dot.rect)
            }
        }
    }

    private func calculateUnSmoothedGlucoseDots() -> [CGRect] {
        glucose.map { value -> CGRect in
            let position = unSmoothedGlucoseToCoordinate(value)
            return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
        }
    }

    private func calculateBolusDots() -> [DotInfo] {
        data.useInsulinBars ? insulinBarEntries() : insulinCircleEntries()
    }

    private func insulinCirclesPath() -> Path {
        Path { path in
            for dot in bolusDots {
                path.addEllipse(in: dot.rect)
            }
        }
    }

    // An InsulinBarMark of sorts
    private func insulinBarsPath() -> Path {
        Path { path in
            for dot in bolusDots {
                let rect = dot.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.maxY + ChartConfig.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY + ChartConfig.pointSizeHeight))
            }
        }
    }

    private func calculateCarbsDots() -> [DotInfo] {
        data.useCarbBars ? carbsBarEntries(realCarbs) : carbsCircleEntries(realCarbs)
    }

    private func carbsCirclesPath(_ dots: [DotInfo]) -> Path {
        Path { path in
            for dot in dots {
                path.addEllipse(in: dot.rect)
            }
        }
    }

    // A BarMark for Carbs
    private func carbsBarsPath(_ dots: [DotInfo]) -> Path {
        Path { path in
            for dot in dots {
                let rect = dot.rect
                path.move(to: CGPoint(x: rect.midX, y: rect.minY - ChartConfig.pointSizeHeight))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.minY - ChartConfig.pointSizeHeight))
            }
        }
    }

    private func calculateFPUsDots() -> [DotInfo] {
        data.useCarbBars ? fpuBarEntries(fpus) : fpuCircleEntries(fpus)
    }

    private func calculatePredictionDots(type: PredictionType) -> [CGRect] {
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

        let dots = values.enumerated().map { index, value -> CGRect in
            let position = predictionToCoordinate(value, index: index)
            return CGRect(x: position.x - 1.3, y: position.y - 1.3, width: 2.6, height: 2.6)
        }

        return dots
    }

    private func calculateBasalPoints() -> (Path, Path) {
        cachedMaxBasalRate = nil
        let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        let firstTempTime = (data.tempBasals.first?.timestamp ?? Date()).timeIntervalSince1970
        var lastTimeEnd = firstTempTime
        let firstRegularBasalPoints = findRegularBasalPoints(
            timeBegin: dayAgoTime,
            timeEnd: firstTempTime,
            autotuned: false
        )
        let tempBasalPoints = firstRegularBasalPoints + data.tempBasals.windows(ofCount: 2).map { chunk -> [CGPoint] in
            let chunk = Array(chunk)
            guard chunk.count == 2, chunk[0].type == .tempBasal, chunk[1].type == .tempBasalDuration else { return [] }
            let timeBegin = chunk[0].timestamp.timeIntervalSince1970
            let timeEnd = timeBegin + (chunk[1].durationMin ?? 0).minutes.timeInterval
            let rateCost = ChartConfig.basalHeight / CGFloat(maxBasalRate())
            let x0 = timeToXCoordinate(timeBegin)
            let y0 = ChartConfig.basalHeight - CGFloat(chunk[0].rate ?? 0) * rateCost
            let regularPoints = findRegularBasalPoints(
                timeBegin: lastTimeEnd,
                timeEnd: timeBegin,
                autotuned: false
            )
            lastTimeEnd = timeEnd
            return regularPoints + [CGPoint(x: x0, y: y0)]
        }.flatMap { $0 }
        let tempBasalPath = Path { path in
            var yPoint: CGFloat = ChartConfig.basalHeight
            path.move(to: CGPoint(x: 0, y: yPoint))

            for point in tempBasalPoints {
                path.addLine(to: CGPoint(x: point.x, y: yPoint))
                path.addLine(to: point)
                yPoint = point.y
            }
            let lastPoint = lastBasalPoint()
            path.addLine(to: CGPoint(x: lastPoint.x, y: yPoint))
            path.addLine(to: CGPoint(x: lastPoint.x, y: ChartConfig.basalHeight))
            path.addLine(to: CGPoint(x: 0, y: ChartConfig.basalHeight))
        }
        let adjustForOptionalExtraHours = data.screenHours > 12 ? data.screenHours - 12 : 0
        let endDateTime = dayAgoTime + min(max(Int(data.screenHours - adjustForOptionalExtraHours), 12), 24).hours
            .timeInterval + min(max(Int(data.screenHours - adjustForOptionalExtraHours), 12), 24).hours
            .timeInterval
        let autotunedBasalPoints = findRegularBasalPoints(
            timeBegin: dayAgoTime,
            timeEnd: endDateTime,
            autotuned: true
        )

        let autotunedBasalPath = Path { path in
            var yPoint: CGFloat = ChartConfig.basalHeight
            path.move(to: CGPoint(x: -50, y: yPoint))

            for point in autotunedBasalPoints {
                path.addLine(to: CGPoint(x: point.x, y: yPoint))
                path.addLine(to: point)
                yPoint = point.y
            }
            path.addLine(to: CGPoint(x: timeToXCoordinate(endDateTime), y: yPoint))
        }

        return (tempBasalPath, autotunedBasalPath)
    }

    private func calculateSuspensions() -> Path {
        var rects = data.suspensions.windows(ofCount: 2).map { window -> CGRect? in
            let window = Array(window)
            guard window[0].type == .pumpSuspend, window[1].type == .pumpResume else { return nil }
            let x0 = self.timeToXCoordinate(window[0].timestamp.timeIntervalSince1970)
            let x1 = self.timeToXCoordinate(window[1].timestamp.timeIntervalSince1970)
            return CGRect(x: x0, y: 0, width: x1 - x0, height: ChartConfig.basalHeight * 0.7)
        }

        let firstRec = data.suspensions.first.flatMap { event -> CGRect? in
            guard event.type == .pumpResume else { return nil }
            let tbrTime = self.data.tempBasals.last { $0.timestamp < event.timestamp }
                .map { $0.timestamp.timeIntervalSince1970 + TimeInterval($0.durationMin ?? 0) * 60 } ?? Date()
                .addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970

            let x0 = self.timeToXCoordinate(tbrTime)
            let x1 = self.timeToXCoordinate(event.timestamp.timeIntervalSince1970)
            return CGRect(
                x: x0,
                y: 0,
                width: x1 - x0,
                height: ChartConfig.basalHeight * 0.7
            )
        }

        let lastRec = data.suspensions.last.flatMap { event -> CGRect? in
            guard event.type == .pumpSuspend else { return nil }
            let tbrTimeX = self.data.tempBasals.first { $0.timestamp > event.timestamp }
                .map { self.timeToXCoordinate($0.timestamp.timeIntervalSince1970) }
            let x0 = self.timeToXCoordinate(event.timestamp.timeIntervalSince1970)

            let x1 = tbrTimeX ?? self.fullGlucoseWidth + self.additionalWidth

            return CGRect(x: x0, y: 0, width: x1 - x0, height: ChartConfig.basalHeight * 0.7)
        }
        rects.append(firstRec)
        rects.append(lastRec)

        return Path { path in
            path.addRects(rects.compactMap { $0 })
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

    private func calculateTempTargetsRects() -> Path {
        var rects = data.tempTargets.map { tempTarget -> CGRect in
            let x0 = timeToXCoordinate(tempTarget.createdAt.timeIntervalSince1970)
            let y0 = glucoseToYCoordinate(Int(tempTarget.targetTop ?? 0))
            let x1 = timeToXCoordinate(
                tempTarget.createdAt.timeIntervalSince1970 + Int(tempTarget.duration).minutes.timeInterval
            )
            let y1 = glucoseToYCoordinate(Int(tempTarget.targetBottom ?? 0))
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
        return Path { path in
            path.addRects(rects)
        }
    }

    private func calculateOverridesRects() -> Path {
        let latest = data.latestOverride
        let rects = data.overrideHistory.map { each -> CGRect in
            let duration = each.duration
            let xStart = timeToXCoordinate(each.date!.timeIntervalSince1970)
            let xEnd = timeToXCoordinate(
                each.date!.addingTimeInterval(Int(duration).minutes.timeInterval).timeIntervalSince1970
            )
            let y = glucoseToYCoordinate(Int(each.target))
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
            let duration = Double(truncating: last.duration ?? 0)
            // Looks better when target isn't == 0 in Home View Main Chart
            let targetRaw = last.target ?? 0
            let target = Int(truncating: targetRaw) < 6 ? 6 : targetRaw

            if duration > 0 {
                let x1 = timeToXCoordinate((latest?.date ?? Date.now).timeIntervalSince1970)
                let plusNow = (last.date ?? Date.now)
                    .addingTimeInterval(Int(truncating: latest?.duration ?? 0).minutes.timeInterval)
                let x2 = timeToXCoordinate(plusNow.timeIntervalSince1970)
                let oneMore = CGRect(
                    x: x1,
                    y: glucoseToYCoordinate(Int(truncating: target)) - 3,
                    width: x2 - x1,
                    height: 6
                )
                old.append(oneMore)
                let path = Path { path in
                    path.addRects(old)
                }
                return path
            } else {
                let x1 = timeToXCoordinate((last.date ?? Date.now).timeIntervalSince1970)
                let x2 = timeToXCoordinate(Date.now.timeIntervalSince1970)
                let oneMore = CGRect(
                    x: x1,
                    y: glucoseToYCoordinate(Int(truncating: target)) - 3,
                    width: x2 - x1 + additionalWidth,
                    height: 6
                )
                old.append(oneMore)
                let path = Path { path in
                    path.addRects(old)
                }
                return path
            }
        }
        return Path { path in
            path.addRects(rects)
        }
    }

    private func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval,
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

                let rateCost = ChartConfig.basalHeight / CGFloat(maxBasalRate())
                if window[0].time < timeBegin, window[1].time >= timeBegin {
                    let x = timeToXCoordinate(timeBegin)
                    let y = ChartConfig.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                if window[0].time >= timeBegin, window[0].time < timeEnd {
                    let x = timeToXCoordinate(window[0].time)
                    let y = ChartConfig.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                return nil
            }
        return basalTruncatedPoints
    }

    private func lastBasalPoint() -> CGPoint {
        let lastBasal = Array(data.tempBasals.suffix(2))
        guard lastBasal.count == 2 else {
            return CGPoint(
                x: timeToXCoordinate(Date().timeIntervalSince1970),
                y: ChartConfig.basalHeight
            )
        }
        let endBasalTime = lastBasal[0].timestamp.timeIntervalSince1970 + (lastBasal[1].durationMin?.minutes.timeInterval ?? 0)
        let rateCost = ChartConfig.basalHeight / CGFloat(maxBasalRate())
        let x = timeToXCoordinate(endBasalTime)
        let y = ChartConfig.basalHeight - CGFloat(lastBasal[0].rate ?? 0) * rateCost
        return CGPoint(x: x, y: y)
    }

    private func calculateFullGlucoseWidth() -> CGFloat {
        fullSize.width * CGFloat(data.hours) / CGFloat(min(max(data.screenHours, 2), 24))
    }

    private func calculateAdditionalWidth() -> CGFloat {
        guard let predictions = data.suggestion?.predictions,
              let deliveredAt = data.suggestion?.deliverAt,
              let last = glucose.last
        else {
            return ChartConfig.minAdditionalWidth
        }

        let max: Int
        if !data.hidePredictions {
            let iob = predictions.iob?.count ?? 0
            let zt = predictions.zt?.count ?? 0
            let cob = predictions.cob?.count ?? 0
            let uam = predictions.uam?.count ?? 0
            max = [iob, zt, cob, uam].max() ?? 0
        } else {
            max = 120 / 5 // multiplied by 5 below, so we get 120 minutes total and 90 minutes clearly visible
        }

        let lastDeltaTime = last.dateString.timeIntervalSince(deliveredAt)

        let additionalTime = CGFloat(TimeInterval(max) * 5.minutes.timeInterval - lastDeltaTime)

        return Swift.min(
            Swift
                .max(
                    additionalTime * oneSecondWidth,
                    data.hidePredictions ? ChartConfig.minAdditionalWidth / 2 : ChartConfig.minAdditionalWidth
                ),
            275
        )
    }

    private func calculateOneSecondStep() -> CGFloat {
        fullSize.width / (CGFloat(min(max(data.screenHours, 2), 24)) * CGFloat(1.hours.timeInterval))
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

    private func activityToCoordinate(date: Date, activity: Decimal) -> CGPoint {
        let x = timeToXCoordinate(date.timeIntervalSince1970)
        let y = activityToYCoordinate(activity)

        return CGPoint(x: x, y: y)
    }

    private func cobToCoordinate(date: Date, cob: Decimal) -> CGPoint {
        let x = timeToXCoordinate(date.timeIntervalSince1970)
        let y = cobToYCoordinate(cob)

        return CGPoint(x: x, y: y)
    }

    private func glucoseToCoordinate(_ glucoseEntry: BloodGlucose) -> CGPoint {
        let x = timeToXCoordinate(glucoseEntry.dateString.timeIntervalSince1970)
        let y = glucoseToYCoordinate(glucoseEntry.glucose ?? 0)

        return CGPoint(x: x, y: y)
    }

    private func unSmoothedGlucoseToCoordinate(_ glucoseEntry: BloodGlucose) -> CGPoint {
        let x = timeToXCoordinate(glucoseEntry.dateString.timeIntervalSince1970)
        let glucoseValue: Decimal = glucoseEntry.unfiltered ?? Decimal(glucoseEntry.glucose ?? 0)
        let y = glucoseToYCoordinate(Int(glucoseValue))

        return CGPoint(x: x, y: y)
    }

    private func predictionToCoordinate(_ pred: Int, index: Int) -> CGPoint {
        guard let deliveredAt = data.suggestion?.deliverAt else {
            return .zero
        }

        let predTime = deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes.timeInterval
        let x = timeToXCoordinate(predTime)
        let y = glucoseToYCoordinate(pred)

        return CGPoint(x: x, y: y)
    }

    private func timeToXCoordinate(_ time: TimeInterval) -> CGFloat {
        let xOffset = -Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        let stepXFraction = fullGlucoseWidth / CGFloat(data.hours.hours.timeInterval)
        let x = CGFloat(time + xOffset) * stepXFraction
        return x
    }

    private func glucoseToYCoordinate(_ glucoseValue: Int) -> CGFloat {
        let topPadding = ChartConfig.topYPadding + ChartConfig.basalHeight
        let bottomPadding = data.showInsulinActivity || data.showCobChart ? ChartConfig
            .mainChartBottomPaddingWithActivity : ChartConfig
            .bottomPadding
        let chartHeight = (fullSize.height - topPadding - bottomPadding)
        let stepYFraction = chartHeight / CGFloat(glucoseMaxValue - glucoseMinValue)
        let yOffset = CGFloat(glucoseMinValue) * stepYFraction
        let y = fullSize.height - CGFloat(glucoseValue) * stepYFraction + yOffset - bottomPadding
        return y
    }

    private func activityToYCoordinate(_ activityValue: Decimal) -> CGFloat {
        let bottomPadding = fullSize.height - ChartConfig.bottomPadding
        let (minValue, maxValue) = activityChartMinMax
        let stepYFraction = ChartConfig.activityChartHeight / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let y = bottomPadding - CGFloat(activityValue) * stepYFraction + yOffset
        return y
    }

    private func cobToYCoordinate(_ cobValue: Decimal) -> CGFloat {
        let bottomPadding = activityZeroPointY ?? (fullSize.height - ChartConfig.bottomPadding)
        let (minValue, maxValue) = cobChartMinMax
        let circleHeight = (ChartConfig.carbsSize + 4.0 + 8.0)
        let stepYFraction = (ChartConfig.cobChartHeight - circleHeight) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let y = bottomPadding - CGFloat(cobValue) * stepYFraction + yOffset
        return y
    }

    private func calculateActivityChartMinMax() -> (Double, Double) {
        let maxIOBPeakActivity = peakActivity_maxIOB * 0.5
        let maxBolusPeakActivity = peakActivity_maxBolus * 1.1
        let maxValue = max(
            maxIOBPeakActivity,
            maxBolusPeakActivity,
            Double(maxActivityInData ?? Decimal(0)) * 1.05
        )
        return (
            -peakActivity_1unit,
            maxValue
        )
    }

    private func calculateCobChartMinMax() -> (Double, Double) {
        return (
            0.0,
            Double(data.cob.map(\.cob).max() ?? 0.0) * 1.2
        )
    }

    // function to calculate the maximum insulin activity for a given bolus size
    // used to scale the activity chart
    private func peakInsulinActivity(forBolus: Double) -> Double {
        let peak = Double(data.insulinPeak)
        let dia = Double(data.insulinDIA)
        let end = dia * 60.0

        // Calculate tau
        let peakOverEnd = peak / end
        let tauNumerator = peak * (1.0 - peakOverEnd)
        let tauDenominator = 1.0 - 2.0 * peakOverEnd
        guard tauDenominator != 0 else {
            return 0.1
        }
        let tau = tauNumerator / tauDenominator

        // Calculate a
        let a = 2.0 * tau / end

        // Calculate S
        let expNegEndOverTau = exp(-end / tau)
        let S = 1.0 / (1.0 - a + (1.0 + a) * expNegEndOverTau)

        // Calculate activity at peak time
        let t = peak
        let activity = forBolus * (S / pow(tau, 2)) * t * (1.0 - t / end) * exp(-t / tau)

        return activity
    }

    // Inverse function to calculate the bolus size needed for a desired peak activity
    // TODO: not tested
    private func bolusForPeakActivity(desiredActivity: Double) -> Double {
        let peak = Double(data.insulinPeak)
        let dia = Double(data.insulinDIA)
        let end = dia * 60.0

        // Calculate tau (same as original function)
        let peakOverEnd = peak / end
        let tauNumerator = peak * (1.0 - peakOverEnd)
        let tauDenominator = 1.0 - 2.0 * peakOverEnd
        guard tauDenominator != 0 else {
            return 0.0
        }
        let tau = tauNumerator / tauDenominator

        // Calculate a (same as original function)
        let a = 2.0 * tau / end

        // Calculate S (same as original function)
        let expNegEndOverTau = exp(-end / tau)
        let S = 1.0 / (1.0 - a + (1.0 + a) * expNegEndOverTau)

        // Calculate the scaling factor at peak time
        let t = peak
        let scalingFactor = (S / pow(tau, 2)) * t * (1.0 - t / end) * exp(-t / tau)

        // Guard against division by zero
        guard scalingFactor != 0 else {
            return 0.0
        }

        // Since activity = forBolus * scalingFactor, then forBolus = activity / scalingFactor
        return desiredActivity / scalingFactor
    }

    private var previousLookupTime: TimeInterval?
    private var glucoseStartIndex = 0

    private func timeToInterpolatedPoint(_ time: TimeInterval) -> CGPoint {
        if let previousLookupTime = previousLookupTime, previousLookupTime > time {
            glucoseStartIndex = 0
        }
        previousLookupTime = time
        let x = timeToXCoordinate(time)

        // Find the first index >= startIndex such that current.time <= time < next.time
        // If not found, fall back to the last glucose entry.

        var matchIndex: Int?

        for i in glucoseStartIndex ..< (glucose.count - 1) {
            let cur = glucose[i]
            let nxt = glucose[i + 1]
            let t0 = cur.dateString.timeIntervalSince1970
            let t1 = nxt.dateString.timeIntervalSince1970
            if t0 <= time, time < t1 {
                matchIndex = i
                break
            }
        }

        // Case 1: Found bracketing pair → weighted average of glucose values by time
        if let i = matchIndex {
            let cur = glucose[i]
            let nxt = glucose[i + 1]
            let t0 = cur.dateString.timeIntervalSince1970
            let t1 = nxt.dateString.timeIntervalSince1970

            let dt = t1 - t0
            if dt <= 0 {
                let y = glucoseToYCoordinate(cur.glucose ?? 0)
                glucoseStartIndex = i // for subsequent searches
                return CGPoint(x: x, y: y)
            }

            // Weighted average of glucose
            let g0 = Double(cur.glucose ?? 0)
            let g1 = Double(nxt.glucose ?? 0)
            let w = (time - t0) / dt
            let g = g0 + (g1 - g0) * w
            let y = glucoseToYCoordinate(Int(g.rounded()))
            glucoseStartIndex = i // for subsequent searches
            return CGPoint(x: x, y: y)
        }

        // Case 2: No match found → use last glucose
        if let last = glucose.last {
            let y = glucoseToYCoordinate(last.glucose ?? 0)
            glucoseStartIndex = glucose.count - 1 // for subsequent searches
            return CGPoint(x: x, y: y)
        }

        return CGPoint(x: x, y: 0)
    }

    private func glucoseMinMaxYValues() -> (min: Int, max: Int) {
        var maxValue = glucose.compactMap(\.glucose).max() ?? ChartConfig.maxGlucose

        if let maxTargetValue = maxTargetValue() {
            maxValue = max(maxValue, maxTargetValue)
        }
        var minValue = glucose.compactMap(\.glucose).min() ?? ChartConfig.minGlucose
        if let minPredValue = minPredValue() {
            minValue = min(minValue, minPredValue)
        }
        if let minTargetValue = minTargetValue() {
            minValue = min(minValue, minTargetValue)
        }

        if minValue == maxValue {
            minValue = ChartConfig.minGlucose
            maxValue = ChartConfig.maxGlucose
        }
        // fix the grah y-axis as long as the min and max BG values are within set borders
        if minValue > ChartConfig.minGlucose {
            minValue = ChartConfig.minGlucose
        }

        return (min: minValue, max: maxValue)
    }

    private func getGlucoseYRange() -> GlucoseYRange {
        let topYPaddint = ChartConfig.topYPadding + ChartConfig.basalHeight
        let mainChartBottomPadding = data.showInsulinActivity || data.showCobChart ? ChartConfig
            .mainChartBottomPaddingWithActivity : ChartConfig.bottomPadding
        let stepYFraction = (fullSize.height - topYPaddint - mainChartBottomPadding) / CGFloat(glucoseMaxValue - glucoseMinValue)
        let yOffset = CGFloat(glucoseMinValue) * stepYFraction
        let maxY = fullSize.height - CGFloat(glucoseMinValue) * stepYFraction + yOffset - mainChartBottomPadding
        let minY = fullSize.height - CGFloat(glucoseMaxValue) * stepYFraction + yOffset - mainChartBottomPadding
        return (minValue: glucoseMinValue, minY: minY, maxValue: glucoseMaxValue, maxY: maxY)
    }

    private func calculateFirstHourDate() -> Date {
        let firstDate = Date().addingTimeInterval(-1.days.timeInterval)
        return firstDate.dateTruncated(from: .minute)!
    }

    private func calculateFirstHourPosition() -> CGFloat {
        let firstDate = Date().addingTimeInterval(-1.days.timeInterval)
        let firstHour = firstHourDate

        let lastDeltaTime = firstHour.timeIntervalSince(firstDate)

        return oneSecondWidth * CGFloat(lastDeltaTime)
    }

    private func insulinCircleEntries() -> [DotInfo] {
        boluses.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970)
            let size = ChartConfig.bolusSize + CGFloat(value.amount ?? 0) * ChartConfig.bolusScale
            let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let bolusValue = value.amount ?? 0
            let string = bolusValue >= data.minimumSMB ? bolusFormatter.string(from: bolusValue as NSNumber) : nil

            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.width / 2,
                        y: rect.minY - ChartConfig.insulinCarbLabelMargin - stringSize.height
                    ),
                    size: CGSize(width: stringSize.width, height: stringSize.height)
                )
            }

            return DotInfo(rect: rect, value: bolusValue, text: string, textRect: textRect)
        }
    }

    private func insulinBarEntries() -> [DotInfo] {
        boluses.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970)
            let bolusValue = value.amount ?? 0
            let height = bolusHeight(amount: bolusValue)
            let rect = CGRect(
                x: center.x,
                y: center.y - height - ChartConfig.insulinOffset,
                width: width(value: bolusValue),
                height: height + ChartConfig.pointSizeHeight
            )
            let string = bolusValue >= data.minimumSMB ? bolusFormatter.string(from: bolusValue as NSNumber) : nil

            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.height / 2,
                        y: rect.minY - ChartConfig.pointSizeHeight - ChartConfig
                            .insulinCarbLabelMargin - stringSize.width
                    ),
                    size: CGSize(width: stringSize.height, height: stringSize.width)
                )
            }

            return DotInfo(rect: rect, value: bolusValue, text: string, textRect: textRect)
        }
    }

    private func carbsCircleEntries(_ realCarbs: [CarbsEntry]) -> [DotInfo] {
        realCarbs.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(
                value.actualDate != nil ?
                    (value.actualDate ?? Date()).timeIntervalSince1970 :
                    value.createdAt.timeIntervalSince1970
            )
            let size = min(
                ChartConfig.maxCarbSize,
                ChartConfig.carbsSize + CGFloat(value.carbs) * ChartConfig.carbsScale
            )
            let rect = CGRect(
                x: center.x - size / 2,
                y: (center.y - size / 2) + ChartConfig.carbOffset + (size / 2),
                width: size,
                height: size // + CGFloat(value.carbs) * ChartConfig.carbsScale
            )

            let string = carbsFormatter.string(from: value.carbs as NSNumber)
            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.width / 2,
                        y: rect.maxY + ChartConfig.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.width, height: stringSize.height)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func carbsBarEntries(_ carbs: [CarbsEntry]) -> [DotInfo] {
        carbs.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(
                (value.actualDate ?? .distantPast).timeIntervalSince1970
            )
            let height = carbHeight(amount: value.carbs)
            let rect = CGRect(
                x: center.x,
                y: center.y + ChartConfig.insulinOffset,
                width: min(width(value: value.carbs), ChartConfig.carbWidth),
                height: height + ChartConfig.pointSizeHeight
            )

            let string = carbsFormatter.string(from: value.carbs as NSNumber)
            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.height / 2,
                        y: rect.maxY + ChartConfig.pointSizeHeight + ChartConfig.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.height, height: stringSize.width)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func fpuCircleEntries(_ fpus: [CarbsEntry]) -> [DotInfo] {
        fpus.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(
                value.actualDate != nil ?
                    (value.actualDate ?? Date()).timeIntervalSince1970 :
                    value.createdAt.timeIntervalSince1970
            )
            let size = ChartConfig.fpuSize + CGFloat(value.carbs) * ChartConfig.fpuScale
            let rect = CGRect(
                x: center.x - size / 2,
                y: center.y + ChartConfig.carbOffset - size / 2,
                width: size,
                height: size
            )

            let string = carbsFormatter.string(from: value.carbs as NSNumber)

            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.width / 2,
                        y: rect.maxY + ChartConfig.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.width, height: stringSize.height)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func fpuBarEntries(_ fpus: [CarbsEntry]) -> [DotInfo] {
        fpus.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(
                (value.actualDate ?? .distantPast).timeIntervalSince1970
            )
            let height = carbHeight(amount: value.carbs)
            let rect = CGRect(
                x: center.x,
                y: center.y + ChartConfig.carbOffset,
                width: min(width(value: value.carbs), 3),
                height: height
            )

            let string = carbsFormatter.string(from: value.carbs as NSNumber)
            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.height / 2,
                        y: rect.maxY + ChartConfig.pointSizeHeight + ChartConfig.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.height, height: stringSize.width)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func bolusHeight(amount: Decimal) -> CGFloat {
        let height = (amount / data.maxBolusValue) * ChartConfig.bolusHeight
        return CGFloat(height)
    }

    private func carbHeight(amount: Decimal) -> CGFloat {
        let height = (amount / data.maxCarbsValue) * ChartConfig.carbHeight
        return CGFloat(height)
    }

    private func width(value: Decimal) -> CGFloat {
        switch data.screenHours {
        case 12:
            return value < data.minimumSMB ? 2.5 : 3
        case 24:
            return value < data.minimumSMB ? 1.5 : 2
        default:
            return value < data.minimumSMB ? 3.5 : 4
        }
    }

    private func getBolusFont() -> (Font, UIFont) {
        var size = CGFloat(12)
        switch data.screenHours {
        case 12:
            size = 9
        case 24:
            size = 7
        default:
            size = 11
        }
        return (
            Font.custom("BolusDotFont", fixedSize: size),
            UIFont.systemFont(ofSize: size)
        )
    }

    private func getPeaksFont() -> (Font, UIFont) {
        var size = CGFloat(12)
        switch data.screenHours {
        case 12:
            size = 11
        case 24:
            size = 9
        default:
            size = 13
        }
        return (
            Font.custom("BolusDotFont", fixedSize: size),
            UIFont.systemFont(ofSize: size)
        )
    }

    private func textSize(text: String, font: UIFont) -> CGSize {
        text.size(withAttributes: [
            .font: font
        ])
    }

    // TODO: remove this
    func measure<T>(_ label: String, _ body: () -> T) -> T {
        let start = Date()
        let result = body()
        let ms = Date().timeIntervalSince(start) * 1000
        print("\(label): \(ms) ms")
        return result
    }
}
