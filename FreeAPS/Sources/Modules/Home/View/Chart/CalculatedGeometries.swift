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

    init(
        fullSize: CGSize,
        data: ChartModel
    ) {
        self.fullSize = fullSize
        self.data = data

        let started = Date.now

        firstHourDate = calculateFirstHourDate()
        oneSecondWidth = calculateOneSecondStep()
        additionalWidth = calculateAdditionalWidth()
        fullGlucoseWidth = calculateFullGlucoseWidth()
        firstHourPosition = calculateFirstHourPosition()
        currentTimeX = timeToXCoordinate(data.timerDate.timeIntervalSince1970)

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
        let (maxima, minima) = PeakPicker.pick(data: data.glucose, windowHours: Double(data.screenHours) / 3.5)

        // y, x-start, x-end, glucose value
        var glucosePeaks: [GlucosePeak] = []

        for peak in maxima {
            if let glucose = peak.glucose {
                let point = glucoseToCoordinate(peak)
                if let (endX, endY) = positionPeak(peak: peak, x: point.x, y: point.y - 18, .max) {
                    glucosePeaks.append(
                        (
                            yStart: point.y,
                            yEnd: endY,
                            xStart: point.x,
                            xEnd: endX,
                            textX: endX,
                            textY: endY,
                            glucose: glucose,
                            .max
                        )
                    )
                }
            }
        }

        for peak in minima {
            if let glucose = peak.glucose {
                let point = glucoseToCoordinate(peak)
                if let (endX, endY) = positionPeak(peak: peak, x: point.x, y: point.y + 18, .min) {
                    glucosePeaks.append(
                        (
                            yStart: point.y,
                            yEnd: endY,
                            xStart: point.x,
                            xEnd: endX,
                            textX: endX,
                            textY: endY,
                            glucose: glucose,
                            .min
                        )
                    )
                }
            }
        }

        return glucosePeaks
    }

    private func positionPeak(peak _: BloodGlucose, x: CGFloat, y: CGFloat, _ type: ExtremumType) -> (CGFloat, CGFloat)? {
        let labelWidth: CGFloat = 36.0
        let labelHeight: CGFloat = 20.0
        let verticalLimit: CGFloat = 80.0
        if type == .max {
            let bolusLabelHeight: CGFloat = data.useInsulinBars ? 20.0 : 8.0
            let bolusLabelWidth: CGFloat = data.useInsulinBars ? 8.0 : 20.0
            return bolusDots.placeLabelCenter(
                desiredCenterX: x,
                desiredCenterY: y,
                labelWidth: labelWidth,
                labelHeight: labelHeight,
                verticalSide: .above,
                verticalLimit: verticalLimit,
                verticalStep: 5,
                maxDotHops: 3,
                dotExtraLabelHeight: bolusLabelHeight,
                dotLabelWidth: bolusLabelWidth
            )
        } else {
            let carbsLabelHeight: CGFloat = data.useCarbBars ? 20.0 : 8.0
            let carbsLabelWidth: CGFloat = data.useCarbBars ? 8.0 : 20.0
            return carbsDots.placeLabelCenter(
                desiredCenterX: x,
                desiredCenterY: y,
                labelWidth: labelWidth,
                labelHeight: labelHeight,
                verticalSide: .below,
                verticalLimit: verticalLimit,
                verticalStep: 5,
                maxDotHops: 3,
                dotExtraLabelHeight: carbsLabelHeight,
                dotLabelWidth: carbsLabelWidth
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
        let dots = data.announcement.map { value -> AnnouncementDot in
            let center = timeToInterpolatedPoint(value.createdAt.timeIntervalSince1970)
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
        let dots = data.useInsulinBars ? insulinBarEntries() :
            (data.boluses.map { value -> DotInfo in
                let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970)
                let size = MainChartView.Config.bolusSize + CGFloat(value.amount ?? 0) * MainChartView.Config.bolusScale
                let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
                return DotInfo(rect: rect, value: value.amount ?? 0)
            })

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
        let dots = data.useCarbBars ? carbsBarEntries(realCarbs) : realCarbs.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(
                value.actualDate != nil ?
                    (value.actualDate ?? Date()).timeIntervalSince1970 :
                    value.createdAt.timeIntervalSince1970
            )
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
            return DotInfo(rect: rect, value: value.carbs)
        }

        let path = Path { path in
            for dot in dots {
                path.addEllipse(in: dot.rect)
            }
        }

        return (dots, path)
    }

    private func calculateFPUsDots() -> ([DotInfo], Path) {
        let fpus = data.carbs.filter { $0.isFPU ?? false }
        let dots = data.useCarbBars ? fpuBarEntries(fpus) : fpus.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(
                value.actualDate != nil ?
                    (value.actualDate ?? Date()).timeIntervalSince1970 :
                    value.createdAt.timeIntervalSince1970
            )
            let size = MainChartView.Config.fpuSize + CGFloat(value.carbs) * MainChartView.Config.fpuScale
            let rect = CGRect(
                x: center.x - size / 2,
                y: center.y + MainChartView.Config.carbOffset - size / 2,
                width: size,
                height: size
            )
            return DotInfo(rect: rect, value: value.carbs)
        }

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
        let (minValue, maxValue) = minMaxYValues()
        let chartHeight = (fullSize.height - topPadding - bottomPadding)
        let stepYFraction = chartHeight / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
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

    private func timeToInterpolatedPoint(_ time: TimeInterval) -> CGPoint {
        var nextIndex = 0
        for (index, value) in data.glucose.enumerated() {
            if value.dateString.timeIntervalSince1970 > time {
                nextIndex = index
                break
            }
        }
        let x = timeToXCoordinate(time)

        guard nextIndex > 0 else {
            let lastY = glucoseToYCoordinate(data.glucose.last?.glucose ?? 0)
            return CGPoint(x: x, y: lastY)
        }

        let prevX = timeToXCoordinate(data.glucose[nextIndex - 1].dateString.timeIntervalSince1970)
        let prevY = glucoseToYCoordinate(data.glucose[nextIndex - 1].glucose ?? 0)
        let nextX = timeToXCoordinate(data.glucose[nextIndex].dateString.timeIntervalSince1970)
        let nextY = glucoseToYCoordinate(data.glucose[nextIndex].glucose ?? 0)
        let delta = nextX - prevX
        let fraction = (x - prevX) / delta

        return pointInLine(CGPoint(x: prevX, y: prevY), CGPoint(x: nextX, y: nextY), fraction)
    }

    private func minMaxYValues() -> (min: Int, max: Int) {
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
        let (minValue, maxValue) = minMaxYValues()
        let stepYFraction = (fullSize.height - topYPaddint - mainChartBottomPadding) / CGFloat(maxValue - minValue)
        let yOffset = CGFloat(minValue) * stepYFraction
        let maxY = fullSize.height - CGFloat(minValue) * stepYFraction + yOffset - mainChartBottomPadding
        let minY = fullSize.height - CGFloat(maxValue) * stepYFraction + yOffset - mainChartBottomPadding
        return (minValue: minValue, minY: minY, maxValue: maxValue, maxY: maxY)
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

    private func insulinBarEntries() -> [DotInfo] {
        data.boluses.map { value -> DotInfo in
            let center = timeToInterpolatedPoint(value.timestamp.timeIntervalSince1970)
            let height = bolusHeight(amount: value.amount ?? 0)
            let rect = CGRect(
                x: center.x,
                y: center.y - height - MainChartView.Config.insulinOffset,
                width: width(value: value.amount ?? 0),
                height: height
            )
            return DotInfo(rect: rect, value: value.amount ?? 0)
        }
    }

    private func carbsBarEntries(_ carbs: [CarbsEntry]) -> [DotInfo] {
        carbs.map { value -> DotInfo in
            let center = timeToInterpolatedPoint((value.actualDate ?? .distantPast).timeIntervalSince1970)
            let height = carbHeight(amount: value.carbs)
            let rect = CGRect(
                x: center.x,
                y: center.y + MainChartView.Config.insulinOffset,
                width: min(width(value: value.carbs), MainChartView.Config.carbWidth),
                height: height
            )
            return DotInfo(rect: rect, value: value.carbs)
        }
    }

    private func fpuBarEntries(_ fpus: [CarbsEntry]) -> [DotInfo] {
        fpus.map { value -> DotInfo in
            let center = timeToInterpolatedPoint((value.actualDate ?? .distantPast).timeIntervalSince1970)
            let height = carbHeight(amount: value.carbs)
            let rect = CGRect(
                x: center.x,
                y: center.y + MainChartView.Config.carbOffset,
                width: min(width(value: value.carbs), 3),
                height: height
            )
            return DotInfo(rect: rect, value: value.carbs)
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
}

private enum VerticalSide {
    case above
    case below
}

private extension Array where Element == DotInfo {
    /// Returns the placed label center (x, y) or nil if no placement fits.
    /// Dots must be sorted by rect.minX.
    func placeLabelCenter(
        desiredCenterX x: CGFloat,
        desiredCenterY y: CGFloat,
        labelWidth: CGFloat,
        labelHeight: CGFloat,
        verticalSide: VerticalSide,
        verticalLimit: CGFloat,
        verticalStep: CGFloat = 1,
        maxDotHops: Int = 3,
        dotExtraLabelHeight: CGFloat, // renamed
        dotLabelWidth: CGFloat
    ) -> (x: CGFloat, y: CGFloat)? {
        let halfW = labelWidth * 0.5
        let halfH = labelHeight * 0.5

        guard !isEmpty else { return (x, y) }

        // Build obstacles: each dot merged with its (potentially wider) label area above it.
        let obstacles: [CGRect] = map { d in
            let r = d.rect
            let dotLabelHalfW = dotLabelWidth * 0.5
            let labelMinX = r.midX - dotLabelHalfW
            let labelMaxX = r.midX + dotLabelHalfW
            let expMinX = Swift.min(r.minX, labelMinX)
            let expMaxX = Swift.max(r.maxX, labelMaxX)
            return CGRect(
                x: expMinX,
                y: r.minY - dotExtraLabelHeight,
                width: expMaxX - expMinX,
                height: r.height + dotExtraLabelHeight
            )
        }

        @inline(__always) func lowerBoundMinX(_ x: CGFloat) -> Int {
            var lo = 0, hi = count
            while lo < hi {
                let mid = (lo + hi) >> 1
                if self[mid].rect.minX > x { hi = mid } else { lo = mid + 1 }
            }
            return lo
        }

        // Gap bounds by left-dot index (as before).
        @inline(__always) func gapBounds(leftIndex i: Int) -> (CGFloat, CGFloat) {
            if i < 0 { return (-.infinity, self[0].rect.minX) }
            if i >= count - 1 { return (self[count - 1].rect.maxX, .infinity) }
            return (self[i].rect.maxX, self[i + 1].rect.minX)
        }

        // Find the closest allowed centerX inside a gap at vertical offset `dy`.
        // Avoids obstacles by subtracting their forbidden center-X intervals.
        func bestCenterInGap(gapStart gs: CGFloat, gapEnd ge: CGFloat, desired: CGFloat, dy: CGFloat) -> CGFloat? {
            let minC = gs + halfW
            let maxC = ge - halfW
            guard minC <= maxC else { return nil }

            let cy = y + dy
            let candMinY = cy - halfH
            let candMaxY = cy + halfH

            // Forbidden center-X intervals due to obstacles that overlap in Y.
            var blocks: [(start: CGFloat, end: CGFloat)] = []
            blocks.reserveCapacity(obstacles.count)
            for o in obstacles {
                if o.maxY <= candMinY || o.minY >= candMaxY { continue } // no Y overlap
                // For collision: centerX in [o.minX - halfW, o.maxX + halfW]
                let s = o.minX - halfW
                let e = o.maxX + halfW
                // Clip to [minC, maxC]
                let cs = Swift.max(s, minC)
                let ce = Swift.min(e, maxC)
                if cs < ce { blocks.append((cs, ce)) }
            }

            if blocks.isEmpty {
                // Entire [minC, maxC] is free; clamp desired.
                return Swift.min(Swift.max(desired, minC), maxC)
            }

            // Merge overlapping blocks.
            blocks.sort { $0.start < $1.start }
            var merged: [(CGFloat, CGFloat)] = []
            var cur = blocks[0]
            for i in 1 ..< blocks.count {
                let b = blocks[i]
                if b.start <= cur.1 {
                    cur.1 = Swift.max(cur.1, b.1)
                } else {
                    merged.append(cur)
                    cur = b
                }
            }
            merged.append(cur)

            // Build allowed intervals as the complement within [minC, maxC].
            var allowed: [(CGFloat, CGFloat)] = []
            var cursor = minC
            for m in merged {
                if m.0 > cursor { allowed.append((cursor, m.0)) }
                cursor = Swift.max(cursor, m.1)
            }
            if cursor < maxC { allowed.append((cursor, maxC)) }
            guard !allowed.isEmpty else { return nil }

            // Pick nearest point to `desired`, prefer right side on ties.
            var bestX = allowed[0].0
            var bestDist = CGFloat.greatestFiniteMagnitude
            var bestIsRight = false

            for (a, b) in allowed {
                let cx = Swift.min(Swift.max(desired, a), b)
                let dist = abs(cx - desired)
                let isRight = cx >= desired
                if dist < bestDist || (dist == bestDist && isRight && !bestIsRight) {
                    bestDist = dist
                    bestX = cx
                    bestIsRight = isRight
                }
            }
            return bestX
        }

        // Vertical offsets to try (increasing movement), respecting side preference.
        func verticalSequence(limit: CGFloat, step: CGFloat, side: VerticalSide) -> [CGFloat] {
            guard limit > 0, step > 0 else { return [0] }
            var list: [CGFloat] = [0]
            let maxK = Int((limit / step).rounded(.down))
            switch side {
            case .above:
                for k in 1 ... maxK { list.append(-CGFloat(k) * step) } // up is negative y
            case .below:
                for k in 1 ... maxK { list.append(CGFloat(k) * step) } // down is positive y
            }
            return list
        }

        let lo = lowerBoundMinX(x)
        let baseLeftIndex = lo - 1
        let vSeq = verticalSequence(limit: verticalLimit, step: verticalStep, side: verticalSide)

        // Helper that tries a (gap, dy) combo and returns (cx, cy) if fits.
        @inline(__always) func tryPlace(gapLeftIndex: Int, dy: CGFloat) -> (CGFloat, CGFloat)? {
            let (gs, ge) = gapBounds(leftIndex: gapLeftIndex)
            guard let cx = bestCenterInGap(gapStart: gs, gapEnd: ge, desired: x, dy: dy) else { return nil }
            return (cx, y + dy)
        }

        // 1) Pure horizontal: right then left (dy = 0).
        for h in 0 ... maxDotHops {
            if let p = tryPlace(gapLeftIndex: baseLeftIndex + h, dy: 0) { return p }
            if h > 0, let p = tryPlace(gapLeftIndex: baseLeftIndex - h, dy: 0) { return p }
        }

        // 2) Vertical + horizontal combos: up/down in place, then right-up/down, then left-up/down.
        for (idx, dy) in vSeq.enumerated() where !(idx == 0 && dy == 0) {
            if let p = tryPlace(gapLeftIndex: baseLeftIndex, dy: dy) { return p }
            for h in 1 ... maxDotHops {
                if let p = tryPlace(gapLeftIndex: baseLeftIndex + h, dy: dy) { return p }
            }
            for h in 1 ... maxDotHops {
                if let p = tryPlace(gapLeftIndex: baseLeftIndex - h, dy: dy) { return p }
            }
        }

        return nil
    }
}
