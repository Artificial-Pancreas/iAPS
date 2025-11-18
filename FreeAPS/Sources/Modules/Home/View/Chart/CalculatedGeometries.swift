import Foundation
import SwiftUI

class CalculatedGeometries {
    private let fullSize: CGSize
    private let data: ChartModel

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

    private(set) var insulinBarsPath = Path()

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
        self.fullSize = fullSize
        self.data = data

        let started = Date.now

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

        let (announcementDots, announcementPath) = calculateAnnouncementDots()
        self.announcementDots = announcementDots
        self.announcementPath = announcementPath

        unSmoothedGlucoseDots = calculateUnSmoothedGlucoseDots()

        let (bolusDots, bolusPath) = calculateBolusDots()
        self.bolusDots = bolusDots
        self.bolusPath = bolusPath

        let (carbsDots, carbsPath) = calculateCarbsDots()
        self.carbsDots = carbsDots
        self.carbsPath = carbsPath

        let (fpuDots, fpuPath) = calculateFPUsDots()
        self.fpuDots = fpuDots
        self.fpuPath = fpuPath

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

        let peaksStarted = Date.now

        glucosePeaks = calculateGlucosePeaks()

        let ended = Date.now

        // TODO: remove this
        print(
            "main chart update: \(ended.timeIntervalSince(started) * 1000) milliseconds, peaks: \(ended.timeIntervalSince(peaksStarted) * 1000) milliseconds"
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

        if let glucoseMin = data.glucose.compactMap(\.glucose).min(),
           let glucoseMax = data.glucose.compactMap(\.glucose).max()
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
        let (maxima, minima) = PeakPicker.pick(data: data.glucose, windowHours: Double(data.screenHours) / 2.0)

        // y, x-start, x-end, glucose value
        var glucosePeaks: [GlucosePeak] = []

        let formatter = data.units == .mmolL ? mmolDotGlucoseFormatter : dotGlucoseFormatter

        let peakHorizontalPadding = MainChartView.Config.peakHorizontalPadding
        let peakVerticalPadding = MainChartView.Config.peakVerticalPadding
        let peakMargin = MainChartView.Config.peakMargin

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
        let dots = data.glucose.map { value -> (CGRect, Int?) in
            let position = glucoseToCoordinate(value)
            return (
                CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: MainChartView.Config.glucoseSize),
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

    private func calculateAnnouncementDots() -> ([AnnouncementDot], Path) {
        var startIndex = 0
        let dots = data.announcement.map { value -> AnnouncementDot in
            let (center, newStartIndex) = timeToInterpolatedPoint(value.createdAt.timeIntervalSince1970, startIndex: startIndex)
            startIndex = newStartIndex
            let size = MainChartView.Config.announcementSize * MainChartView.Config.announcementScale
            let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let note = value.notes
            return AnnouncementDot(rect: rect, value: 10, note: note)
        }
        let path = Path { path in
            for dot in dots {
                path.addEllipse(in: dot.rect)
            }
        }
        return (dots, path)
    }

    private func calculateUnSmoothedGlucoseDots() -> [CGRect] {
        data.glucose.map { value -> CGRect in
            let position = unSmoothedGlucoseToCoordinate(value)
            return CGRect(x: position.x - 2, y: position.y - 2, width: 4, height: 4)
        }
    }

    private func calculateBolusDots() -> ([DotInfo], Path) {
        let dots = data.useInsulinBars ? insulinBarEntries() : insulinCircleEntries()

        let path = Path { path in
            for dot in dots {
                path.addEllipse(in: dot.rect)
            }
        }

        return (
            dots,
            path
        )
    }

    private func calculateCarbsDots() -> ([DotInfo], Path) {
        let realCarbs = data.carbs.filter { !($0.isFPU ?? false) }
        let dots = data.useCarbBars ? carbsBarEntries(realCarbs) : carbsCircleEntries(realCarbs)

        let path = Path { path in
            for dot in dots {
                path.addEllipse(in: dot.rect)
            }
        }

        return (dots, path)
    }

    private func calculateFPUsDots() -> ([DotInfo], Path) {
        let fpus = data.carbs.filter { $0.isFPU ?? false }
        let dots = data.useCarbBars ? fpuBarEntries(fpus) : fpuCircleEntries(fpus)

        let path = Path { path in
            for dot in dots {
                path.addEllipse(in: dot.rect)
            }
        }

        return (dots, path)
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
            let rateCost = MainChartView.Config.basalHeight / CGFloat(maxBasalRate())
            let x0 = timeToXCoordinate(timeBegin)
            let y0 = MainChartView.Config.basalHeight - CGFloat(chunk[0].rate ?? 0) * rateCost
            let regularPoints = findRegularBasalPoints(
                timeBegin: lastTimeEnd,
                timeEnd: timeBegin,
                autotuned: false
            )
            lastTimeEnd = timeEnd
            return regularPoints + [CGPoint(x: x0, y: y0)]
        }.flatMap { $0 }
        let tempBasalPath = Path { path in
            var yPoint: CGFloat = MainChartView.Config.basalHeight
            path.move(to: CGPoint(x: 0, y: yPoint))

            for point in tempBasalPoints {
                path.addLine(to: CGPoint(x: point.x, y: yPoint))
                path.addLine(to: point)
                yPoint = point.y
            }
            let lastPoint = lastBasalPoint()
            path.addLine(to: CGPoint(x: lastPoint.x, y: yPoint))
            path.addLine(to: CGPoint(x: lastPoint.x, y: MainChartView.Config.basalHeight))
            path.addLine(to: CGPoint(x: 0, y: MainChartView.Config.basalHeight))
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
            var yPoint: CGFloat = MainChartView.Config.basalHeight
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
            return CGRect(x: x0, y: 0, width: x1 - x0, height: MainChartView.Config.basalHeight * 0.7)
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
                height: MainChartView.Config.basalHeight * 0.7
            )
        }

        let lastRec = data.suspensions.last.flatMap { event -> CGRect? in
            guard event.type == .pumpSuspend else { return nil }
            let tbrTimeX = self.data.tempBasals.first { $0.timestamp > event.timestamp }
                .map { self.timeToXCoordinate($0.timestamp.timeIntervalSince1970) }
            let x0 = self.timeToXCoordinate(event.timestamp.timeIntervalSince1970)

            let x1 = tbrTimeX ?? self.fullGlucoseWidth + self.additionalWidth

            return CGRect(x: x0, y: 0, width: x1 - x0, height: MainChartView.Config.basalHeight * 0.7)
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
        let latest = OverrideStorage().fetchLatestOverride().first
        let rects = data.overrideHistory.compactMap { each -> CGRect in
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

                let rateCost = MainChartView.Config.basalHeight / CGFloat(maxBasalRate())
                if window[0].time < timeBegin, window[1].time >= timeBegin {
                    let x = timeToXCoordinate(timeBegin)
                    let y = MainChartView.Config.basalHeight - CGFloat(window[0].rate) * rateCost
                    return CGPoint(x: x, y: y)
                }

                if window[0].time >= timeBegin, window[0].time < timeEnd {
                    let x = timeToXCoordinate(window[0].time)
                    let y = MainChartView.Config.basalHeight - CGFloat(window[0].rate) * rateCost
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
                y: MainChartView.Config.basalHeight
            )
        }
        let endBasalTime = lastBasal[0].timestamp.timeIntervalSince1970 + (lastBasal[1].durationMin?.minutes.timeInterval ?? 0)
        let rateCost = MainChartView.Config.basalHeight / CGFloat(maxBasalRate())
        let x = timeToXCoordinate(endBasalTime)
        let y = MainChartView.Config.basalHeight - CGFloat(lastBasal[0].rate ?? 0) * rateCost
        return CGPoint(x: x, y: y)
    }

    private func calculateFullGlucoseWidth() -> CGFloat {
        fullSize.width * CGFloat(data.hours) / CGFloat(min(max(data.screenHours, 2), 24))
    }

    private func calculateAdditionalWidth() -> CGFloat {
        guard let predictions = data.suggestion?.predictions,
              let deliveredAt = data.suggestion?.deliverAt,
              let last = data.glucose.last
        else {
            return MainChartView.Config.minAdditionalWidth
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
                    data.hidePredictions ? MainChartView.Config.minAdditionalWidth / 2 : MainChartView.Config.minAdditionalWidth
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
        let topPadding = MainChartView.Config.topYPadding + MainChartView.Config.basalHeight
        let bottomPadding = data.showInsulinActivity || data.showCobChart ? MainChartView.Config
            .mainChartBottomPaddingWithActivity : MainChartView.Config
            .bottomPadding
        let chartHeight = (fullSize.height - topPadding - bottomPadding)
        let stepYFraction = chartHeight / CGFloat(glucoseMaxValue - glucoseMinValue)
        let yOffset = CGFloat(glucoseMinValue) * stepYFraction
        let y = fullSize.height - CGFloat(glucoseValue) * stepYFraction + yOffset - bottomPadding
        return y
    }

    private func activityToYCoordinate(_ activityValue: Decimal) -> CGFloat {
        let bottomPadding = fullSize.height - MainChartView.Config.bottomPadding
        let (minValue, maxValue) = activityChartMinMax
        let stepYFraction = MainChartView.Config.activityChartHeight / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let y = bottomPadding - CGFloat(activityValue) * stepYFraction + yOffset
        return y
    }

    private func cobToYCoordinate(_ cobValue: Decimal) -> CGFloat {
        let bottomPadding = activityZeroPointY ?? (fullSize.height - MainChartView.Config.bottomPadding)
        let (minValue, maxValue) = cobChartMinMax
        let circleHeight = (MainChartView.Config.carbsSize + 4.0 + 8.0)
        let stepYFraction = (MainChartView.Config.cobChartHeight - circleHeight) / CGFloat(maxValue - minValue)
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

    private func timeToInterpolatedPoint(_ time: TimeInterval, startIndex: Int) -> (CGPoint, Int) {
        var nextIndex = startIndex
        for (index, value) in data.glucose.enumerated().dropFirst(startIndex) {
            if value.dateString.timeIntervalSince1970 > time {
                nextIndex = index
                break
            }
        }
        let x = timeToXCoordinate(time)

        guard nextIndex > 0 else {
            let lastY = glucoseToYCoordinate(data.glucose.last?.glucose ?? 0)
            return (CGPoint(x: x, y: lastY), nextIndex)
        }

        let prevX = timeToXCoordinate(data.glucose[nextIndex - 1].dateString.timeIntervalSince1970)
        let prevY = glucoseToYCoordinate(data.glucose[nextIndex - 1].glucose ?? 0)
        let nextX = timeToXCoordinate(data.glucose[nextIndex].dateString.timeIntervalSince1970)
        let nextY = glucoseToYCoordinate(data.glucose[nextIndex].glucose ?? 0)
        let delta = nextX - prevX
        let fraction = (x - prevX) / delta

        return (pointInLine(CGPoint(x: prevX, y: prevY), CGPoint(x: nextX, y: nextY), fraction), nextIndex)
    }

    private func glucoseMinMaxYValues() -> (min: Int, max: Int) {
        var maxValue = data.glucose.compactMap(\.glucose).max() ?? MainChartView.Config.maxGlucose

        if let maxTargetValue = maxTargetValue() {
            maxValue = max(maxValue, maxTargetValue)
        }
        var minValue = data.glucose.compactMap(\.glucose).min() ?? MainChartView.Config.minGlucose
        if let minPredValue = minPredValue() {
            minValue = min(minValue, minPredValue)
        }
        if let minTargetValue = minTargetValue() {
            minValue = min(minValue, minTargetValue)
        }

        if minValue == maxValue {
            minValue = MainChartView.Config.minGlucose
            maxValue = MainChartView.Config.maxGlucose
        }
        // fix the grah y-axis as long as the min and max BG values are within set borders
        if minValue > MainChartView.Config.minGlucose {
            minValue = MainChartView.Config.minGlucose
        }

        return (min: minValue, max: maxValue)
    }

    private func getGlucoseYRange() -> GlucoseYRange {
        let topYPaddint = MainChartView.Config.topYPadding + MainChartView.Config.basalHeight
        let mainChartBottomPadding = data.showInsulinActivity || data.showCobChart ? MainChartView.Config
            .mainChartBottomPaddingWithActivity : MainChartView.Config.bottomPadding
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
        var startIndex = 0
        return data.boluses.map { value -> DotInfo in
            let (center, newStartIndex) = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970, startIndex: startIndex)
            startIndex = newStartIndex
            let size = MainChartView.Config.bolusSize + CGFloat(value.amount ?? 0) * MainChartView.Config.bolusScale
            let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            let bolusValue = value.amount ?? 0
            let string = bolusValue >= data.minimumSMB ? bolusFormatter.string(from: bolusValue as NSNumber) : nil

            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.width / 2,
                        y: rect.minY - MainChartView.Config.insulinCarbLabelMargin - stringSize.height
                    ),
                    size: CGSize(width: stringSize.width, height: stringSize.height)
                )
            }

            return DotInfo(rect: rect, value: bolusValue, text: string, textRect: textRect)
        }
    }

    private func insulinBarEntries() -> [DotInfo] {
        var startIndex = 0
        return data.boluses.map { value -> DotInfo in
            let (center, newStartIndex) = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970, startIndex: startIndex)
            startIndex = newStartIndex
            let bolusValue = value.amount ?? 0
            let height = bolusHeight(amount: bolusValue)
            let rect = CGRect(
                x: center.x,
                y: center.y - height - MainChartView.Config.insulinOffset,
                width: width(value: bolusValue),
                height: height + MainChartView.Config.pointSizeHeight
            )
            let string = bolusValue >= data.minimumSMB ? bolusFormatter.string(from: bolusValue as NSNumber) : nil

            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.height / 2,
                        y: rect.minY - MainChartView.Config.pointSizeHeight - MainChartView.Config
                            .insulinCarbLabelMargin - stringSize.width
                    ),
                    size: CGSize(width: stringSize.height, height: stringSize.width)
                )
            }

            return DotInfo(rect: rect, value: bolusValue, text: string, textRect: textRect)
        }
    }

    private func carbsCircleEntries(_ realCarbs: [CarbsEntry]) -> [DotInfo] {
        var startIndex = 0
        return realCarbs.map { value -> DotInfo in
            let (center, newStartIndex) = timeToInterpolatedPoint(
                value.actualDate != nil ?
                    (value.actualDate ?? Date()).timeIntervalSince1970 :
                    value.createdAt.timeIntervalSince1970,
                startIndex: startIndex
            )
            startIndex = newStartIndex
            let size = min(
                MainChartView.Config.maxCarbSize,
                MainChartView.Config.carbsSize + CGFloat(value.carbs) * MainChartView.Config.carbsScale
            )
            let rect = CGRect(
                x: center.x - size / 2,
                y: (center.y - size / 2) + MainChartView.Config.carbOffset + (size / 2),
                width: size,
                height: size // + CGFloat(value.carbs) * MainChartView.Config.carbsScale
            )

            let string = carbsFormatter.string(from: value.carbs as NSNumber)
            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.width / 2,
                        y: rect.maxY + MainChartView.Config.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.width, height: stringSize.height)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func carbsBarEntries(_ carbs: [CarbsEntry]) -> [DotInfo] {
        var startIndex = 0
        return carbs.map { value -> DotInfo in
            let (center, newStartIndex) = timeToInterpolatedPoint(
                (value.actualDate ?? .distantPast).timeIntervalSince1970,
                startIndex: startIndex
            )
            startIndex = newStartIndex
            let height = carbHeight(amount: value.carbs)
            let rect = CGRect(
                x: center.x,
                y: center.y + MainChartView.Config.insulinOffset,
                width: min(width(value: value.carbs), MainChartView.Config.carbWidth),
                height: height + MainChartView.Config.pointSizeHeight
            )

            let string = carbsFormatter.string(from: value.carbs as NSNumber)
            var textRect: CGRect?
            if let string {
                let stringSize = textSize(text: string, font: bolusUIFont)

                textRect = CGRect(
                    origin: CGPoint(
                        x: rect.midX - stringSize.height / 2,
                        y: rect.maxY + MainChartView.Config.pointSizeHeight + MainChartView.Config.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.height, height: stringSize.width)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func fpuCircleEntries(_ fpus: [CarbsEntry]) -> [DotInfo] {
        var startIndex = 0
        return fpus.map { value -> DotInfo in
            let (center, newStartIndex) = timeToInterpolatedPoint(
                value.actualDate != nil ?
                    (value.actualDate ?? Date()).timeIntervalSince1970 :
                    value.createdAt.timeIntervalSince1970,
                startIndex: startIndex
            )
            startIndex = newStartIndex
            let size = MainChartView.Config.fpuSize + CGFloat(value.carbs) * MainChartView.Config.fpuScale
            let rect = CGRect(
                x: center.x - size / 2,
                y: center.y + MainChartView.Config.carbOffset - size / 2,
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
                        y: rect.maxY + MainChartView.Config.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.width, height: stringSize.height)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func fpuBarEntries(_ fpus: [CarbsEntry]) -> [DotInfo] {
        var startIndex = 0
        return fpus.map { value -> DotInfo in
            let (center, newStartIndex) = timeToInterpolatedPoint(
                (value.actualDate ?? .distantPast).timeIntervalSince1970,
                startIndex: startIndex
            )
            startIndex = newStartIndex
            let height = carbHeight(amount: value.carbs)
            let rect = CGRect(
                x: center.x,
                y: center.y + MainChartView.Config.carbOffset,
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
                        y: rect.maxY + MainChartView.Config.pointSizeHeight + MainChartView.Config.insulinCarbLabelMargin
                    ),
                    size: CGSize(width: stringSize.height, height: stringSize.width)
                )
            }

            return DotInfo(rect: rect, value: value.carbs, text: string, textRect: textRect)
        }
    }

    private func bolusHeight(amount: Decimal) -> CGFloat {
        let height = (amount / data.maxBolusValue) * MainChartView.Config.bolusHeight
        return CGFloat(height)
    }

    private func carbHeight(amount: Decimal) -> CGFloat {
        let height = (amount / data.maxCarbsValue) * MainChartView.Config.carbHeight
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
}

private enum VerticalSide {
    case above
    case below
}

private struct Candidate { let p: CGPoint
    let d: CGFloat
    let rank: Int }

private struct Pick { let p: CGPoint
    let d2: CGFloat
    let rank: Int }

private extension Array where Element == DotInfo {
    /// Place `desired` as the globally closest collision-free rect near `desired`,
    /// ranking by weighted distance where vertical moves cost more.
    /// - Uses expanded obstacles to compute exact same-row gaps (no L/R bias).
    /// - Also tries roofline slabs (above/below) and direct-over each obstacle.
    func placeLabelCenter(
        desiredRect desired: CGRect,
        verticalSide: VerticalSide,
        maxDistance: CGFloat,
        verticalClearanceEps: CGFloat = 0.5,
        verticalWeight: CGFloat = 2.0
    ) -> CGRect? {
        // --- geometry
        let w = desired.width, h = desired.height
        let halfW = w * 0.5, halfH = h * 0.5
        let cx = desired.midX, cy = desired.midY
        let maxD2 = maxDistance * maxDistance

        @inline(__always) func euclidD2(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let dx = x - cx, dy = y - cy
            return dx * dx + dy * dy
        }
        @inline(__always) func cost(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
            let dx = x - cx, dy = y - cy
            let vy = verticalWeight * dy
            return dx * dx + vy * vy
        }
        @inline(__always) func rectAt(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: x - halfW, y: y - halfH, width: w, height: h)
        }

        // Obstacles as rendered (dot + optional text)
        var obstacles: [CGRect] = []
        obstacles.reserveCapacity(Swift.max(1, count * 2))
        for d in self {
            obstacles.append(d.rect)
            if let t = d.textRect { obstacles.append(t) }
        }

        @inline(__always) func intersectsAny(_ r: CGRect) -> Bool {
            for o in obstacles where o.intersects(r) { return true }
            return false
        }

        // If desired already OK, keep it.
        if !intersectsAny(desired) { return desired }

        // Prefilter obstacles to a search box around the Euclidean circle (speeds things up).
        if !obstacles.isEmpty {
            let searchBox = CGRect(
                x: cx - maxDistance - halfW,
                y: cy - maxDistance - halfH,
                width: 2 * (maxDistance + halfW),
                height: 2 * (maxDistance + halfH)
            )
            obstacles.removeAll { !searchBox.intersects($0) }
        }

        // Expanded obstacles for **centers** (Minkowski by label half-size)
        var expanded: [CGRect] = []
        expanded.reserveCapacity(obstacles.count)
        for o in obstacles {
            expanded.append(CGRect(
                x: o.minX - halfW,
                y: o.minY - halfH,
                width: o.width + w,
                height: o.height + h
            ))
        }

        // --- candidate accumulator (weighted cost, tie-break Euclidean)
        var bestRect: CGRect?
        var bestCost = CGFloat.greatestFiniteMagnitude
        var bestEuclid = CGFloat.greatestFiniteMagnitude

        @inline(__always) func considerXY(_ x: CGFloat, _ y: CGFloat) {
            let e2 = euclidD2(x, y)
            if e2 > maxD2 { return }
            let r = rectAt(x, y)
            if intersectsAny(r) { return } // should be false for center-from-expanded, but keep as guard
            let c = cost(x, y)
            if c < bestCost - 1E-6 || (Swift.abs(c - bestCost) <= 1E-6 && e2 < bestEuclid) {
                bestCost = c
                bestEuclid = e2
                bestRect = r
            }
        }

        // ---------- A) SAME ROW (y == cy) via expanded obstacles ----------
        // Blocks for center-X are simply [e.minX, e.maxX] for all expanded e that cover cy.
        func sameRowAllowedIntervals() -> [(CGFloat, CGFloat)] {
            var blocks: [(CGFloat, CGFloat)] = []
            for e in expanded where e.minY <= cy && cy <= e.maxY {
                blocks.append((e.minX, e.maxX))
            }
            if blocks.isEmpty { return [(-CGFloat.infinity, CGFloat.infinity)] }

            blocks.sort { $0.0 < $1.0 }
            var merged: [(CGFloat, CGFloat)] = []
            var cur = blocks[0]
            for i in 1 ..< blocks.count {
                let b = blocks[i]
                if b.0 <= cur.1 { cur.1 = Swift.max(cur.1, b.1) } else { merged.append(cur)
                    cur = b }
            }
            merged.append(cur)

            // Complement → allowed intervals
            var allowed: [(CGFloat, CGFloat)] = []
            var cursor = -CGFloat.infinity
            for m in merged {
                if m.0 > cursor { allowed.append((cursor, m.0)) }
                cursor = Swift.max(cursor, m.1)
            }
            if cursor < CGFloat.infinity { allowed.append((cursor, CGFloat.infinity)) }
            return allowed
        }

        // Evaluate ALL same-row gaps: nearest x in each gap (this removes any L/R bias)
        do {
            let intervals = sameRowAllowedIntervals()
            for (a, b) in intervals {
                let x = Swift.min(Swift.max(cx, a), b)
                if x.isFinite { considerXY(x, cy) }
            }
        }

        // ---------- B) ROOFLINE (above/below), evaluated by x-slabs ----------
        // Collect vertical edges of expanded obstacles within the horizontal search band.
        let xMin = cx - maxDistance, xMax = cx + maxDistance
        var breaks: [CGFloat] = [xMin, cx, xMax]
        breaks.reserveCapacity(Swift.max(3, 2 * expanded.count + 3))
        for e in expanded {
            if e.minX >= xMin - 1E-6, e.minX <= xMax + 1E-6 { breaks.append(e.minX) }
            if e.maxX >= xMin - 1E-6, e.maxX <= xMax + 1E-6 { breaks.append(e.maxX) }
        }
        breaks.sort()
        var xs: [CGFloat] = []
        xs.reserveCapacity(breaks.count)
        var lastX: CGFloat?
        for v in breaks {
            if let L = lastX, Swift.abs(v - L) < 0.25 { continue }
            xs.append(v)
            lastX = v
        }

        func roofY(in slabA: CGFloat, _ slabB: CGFloat) -> CGFloat? {
            var yVal: CGFloat?
            for e in expanded where !(e.maxX <= slabA || e.minX >= slabB) {
                switch verticalSide {
                case .above:
                    let y = e.minY - verticalClearanceEps // strictly above roof
                    yVal = (yVal == nil) ? y : Swift.min(yVal!, y)
                case .below:
                    let y = e.maxY + verticalClearanceEps // strictly below floor
                    yVal = (yVal == nil) ? y : Swift.max(yVal!, y)
                }
            }
            return yVal
        }

        if xs.count >= 2 {
            for i in 0 ..< (xs.count - 1) {
                let a = xs[i], b = xs[i + 1]
                if b <= a { continue }
                guard var y = roofY(in: a, b) else { continue }
                // respect direction relative to original row
                if verticalSide == .above { y = Swift.min(y, cy) } else { y = Swift.max(y, cy) }
                let x = Swift.min(Swift.max(cx, a), b) // nearest x in this slab
                considerXY(x, y)
            }
        }

        // ---------- C) DIRECT-OVER each expanded obstacle (good in tight clusters) ----------
        for e in expanded {
            let y = (verticalSide == .above)
                ? Swift.min(e.minY - verticalClearanceEps, cy)
                : Swift.max(e.maxY + verticalClearanceEps, cy)
            let xMid = Swift.min(Swift.max(cx, e.minX), e.maxX)
            considerXY(xMid, y)
            considerXY(e.minX, y)
            considerXY(e.maxX, y)
        }

        return bestRect
    }
}
