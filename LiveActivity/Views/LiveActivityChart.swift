import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityChart: View {
    let context: ActivityViewContext<LiveActivityAttributes>
    var isWatch: Bool = false

    private let EventualSymbol = "⇢"
    private let dropWidth = CGFloat(80)
    private let dropHeight = CGFloat(80)

    private let decimalString: String = {
        let formatter = NumberFormatter()
        return formatter.decimalSeparator
    }()

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

    var body: some View {
        Group {
            if isWatch {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        watchIOBCOBView(context.state)
                        Spacer()
                        if context.isStale || Date().timeIntervalSince(context.state.loopDate) > 7 * 60 {
                            updatedLabel(context: context)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(.loopRed))
                                .brightness(0.3)
                        }
                        Spacer()
                        glucoseDisplayWatch(context.state)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)

                    chartView(for: context.state)
                        .padding(.bottom, 4)
                        .padding(.leading, 5)
                        .padding(.trailing, 5)
                }
            } else {
                HStack(alignment: .top) {
                    chartView(for: context.state)
                        .padding(.bottom, 10)
                        .padding(.top, 30)
                        .padding(.leading, 15)
                        .padding(.trailing, 10)
                        .background(.black.opacity(0.30))

                    ZStack(alignment: .topTrailing) {
                        VStack(alignment: .trailing, spacing: 0) {
                            chartRightHandView(for: context)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxHeight: .infinity)
                    .padding(.top, 15)
                    .padding(.bottom, 15)
                    .padding(.trailing, 15)
                }
                .overlay {
                    ZStack {
                        timeAndEventualOverlay(for: context)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .privacySensitive()
        .padding(0)
        .background(Color.black.opacity(0.6))
        .activityBackgroundTint(Color.clear)
    }

    private func chartView(for state: LiveActivityAttributes.ContentState) -> some View {
        let ConversionConstant: Double = (state.mmol ? 0.0555 : 1)

        let predictions = isWatch ? limitedPredictions(state.predictions, to: 10) : state.predictions

        // Prediction data
        let iob: [Int16] = predictions?.iob?.values ?? []
        let cob: [Int16] = predictions?.cob?.values ?? []
        let zt: [Int16] = predictions?.zt?.values ?? []
        let uam: [Int16] = predictions?.uam?.values ?? []

        // Prepare for domain range
        let lowThreshold = Double(state.chartLowThreshold) * ConversionConstant
        let highThreshold = Double(state.chartHighThreshold) * ConversionConstant

        // Min/max BG values
        let minValue = state.readings?.values.min().map({ Double($0) * ConversionConstant })
        let maxValue = state.readings?.values.max().map({ Double($0) * ConversionConstant })

        // Green AreaMark low/high
        let yStart = lowThreshold
        let yEnd = highThreshold
        let xStart = state.readings?.dates.min()
        let xEnd = maxOptional(
            predictions?.iob?.dates.max(),
            predictions?.cob?.dates.max(),
            predictions?.zt?.dates.max(),
            predictions?.uam?.dates.max(),
            state.readings?.dates.max()
        )

        // Min/max Predction values
        let maxPrediction = maxOptional(
            iob.max(), cob.max(), zt.max(), uam.max()
        ).map({ Double($0) * ConversionConstant })

        let minPrediction = minOptional(
            iob.max(), cob.max(), zt.max(), uam.max()
        ).map({ Double($0) * ConversionConstant })

        // Dymamic scaling and avoiding any fatal crashes due to out of bounds errors. Never higher than 400 mg/dl
        let yDomainMin = minOptional1(
            lowThreshold * 0.9,
            minValue.map({ $0 * 0.9 }),
            minPrediction
        )
        let yDomainMax = maxOptional1(
            highThreshold * 1.1,
            maxValue.map({ $0 * 1.1 }),
            maxPrediction
        )
        let yDomain = (
            max(yDomainMin, 0) ... min(yDomainMax, 400 * ConversionConstant)
        )

        let glucoseFormatter: FloatingPointFormatStyle<Double> =
            state.mmol ?
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US")) :
            .number.precision(.fractionLength(0))

        let readingsSymbolSize = CGFloat(15)

        let bgOpacity: Double = 0.7
        let predictionsOpacity = 0.3
        let predictionsSymbolSize = CGFloat(10)
        let inRangeRectOpacity = 0.1

        let bgPoints = state.readings.map({
            makePoints($0.dates, $0.values, conversion: ConversionConstant)
        })
        let iobPoints = predictions?.iob.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })
        let ztPoints = predictions?.zt.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })
        let cobPoints = predictions?.cob.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })
        let uamPoints = predictions?.uam.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })

        let nowDate = Date()
        let xScaleEnd: Date = isWatch ? max(xEnd ?? nowDate, nowDate) : (xEnd ?? nowDate)

        return Chart {
            if let bg = bgPoints {
                ForEach(bg, id: \.date) {
                    if $0.value < lowThreshold {
                        PointMark(
                            x: .value("Time", $0.date),
                            y: .value("GlucoseLow", $0.value)
                        )
                        .symbolSize(readingsSymbolSize)
                        .foregroundStyle(.red)
                    } else if $0.value > highThreshold {
                        PointMark(
                            x: .value("Time", $0.date),
                            y: .value("GlucoseHigh", $0.value)
                        )
                        .symbolSize(readingsSymbolSize)
                        .foregroundStyle(.orange)
                    } else {
                        PointMark(
                            x: .value("Time", $0.date),
                            y: .value("Glucose", $0.value)
                        )
                        .symbolSize(readingsSymbolSize)
                        .foregroundStyle(Color(.darkGreen))
                    }
                    LineMark(
                        x: .value("Time", $0.date),
                        y: .value("Glucose", $0.value)
                    )
                    .foregroundStyle(Color(.darkerGray))
                    .opacity(bgOpacity)
                    .lineStyle(StrokeStyle(lineWidth: 1.0))
                }
            }

            if let iob = iobPoints {
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

            if let zt = ztPoints {
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

            if let cob = cobPoints {
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

            if let uam = uamPoints {
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

            if isWatch {
                RuleMark(x: .value("Now", nowDate))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }

            if let xStart = xStart, let xEnd = xEnd {
                RectangleMark(
                    xStart: .value("Start", xStart),
                    xEnd: .value("End", isWatch ? xScaleEnd : xEnd),
                    yStart: .value("Bottom", yStart),
                    yEnd: .value("Top", yEnd)
                )
                .foregroundStyle(.secondary.opacity(inRangeRectOpacity))
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(position: .bottom, values: .stride(by: .hour, count: 1)) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.2))
                if !isWatch {
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .chartYAxis {
            if let minValue, let maxValue {
                AxisMarks(
                    position: isWatch ? .trailing : .leading,
                    values:
                    abs(maxValue - minValue) < 0.8 ? [
                        (maxValue + minValue) / 2
                    ] :
                        [
                            minValue,
                            maxValue
                        ]
                ) { _ in
                    AxisValueLabel(
                        format: glucoseFormatter,
                        horizontalSpacing: isWatch ? 8 : 10
                    )
                    .foregroundStyle(.secondary)
                    .font(isWatch ? .system(size: 12) : .caption)
                }
            }
        }
        .applyingChartXScale(domain: isWatch ? xStart.map { $0 ... xScaleEnd } : nil)
    }

    @ViewBuilder private func chartRightHandView(for context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        glucoseDrop(context.state).offset(y: -7)
            .frame(width: dropWidth, height: dropHeight)

        Grid(horizontalSpacing: 0) {
            GridRow {
                HStack(spacing: 0.5) {
                    Text(context.state.iob)
                        .font(.system(size: 20))
                        .foregroundStyle(Color(.insulin))
                    Text("U")
                        .font(.system(size: 20).smallCaps())
                        .foregroundStyle(Color(.insulin))
                }
                .fontWidth(.condensed)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 0.5) {
                    Text(context.state.cob)
                        .foregroundStyle(Color(.loopYellow))
                    Text("g")
                        .foregroundStyle(Color(.loopYellow))
                }
                .font(.system(size: 20))
                .fontWidth(.condensed)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: dropWidth)
    }

    @ViewBuilder private func timeAndEventualOverlay(for context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        // Eventual Glucose
        HStack(spacing: 4) {
            Text(EventualSymbol)
                .font(.system(size: 16))
                .opacity(0.7)

            Text(context.state.eventual)
                .font(.system(size: 16))
                .opacity(0.8)
                .fontWidth(.condensed)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 10)
        .padding(.trailing, 110)

        // Timestamp
        updatedLabel(context: context)
            .font(.system(size: 11))
            .foregroundStyle(context.isStale ? Color(.loopRed) : .white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 10).padding(.leading, 50)
    }

    @ViewBuilder private func watchIOBCOBView(_ state: LiveActivityAttributes.ContentState) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 0.5) {
                Text(state.iob)
                    .font(.system(size: 19))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                Text("U")
                    .font(.system(size: 19).smallCaps())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .fontWidth(.compressed)

            if state.cob != "0" {
                HStack(spacing: 0.5) {
                    Text(state.cob)
                        .font(.system(size: 19))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                    Text("g")
                        .font(.system(size: 19))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .fontWidth(.compressed)
            }
        }
    }

    @ViewBuilder private func chartRightHandViewWatch(for context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            glucoseDisplayWatch(context.state)

            updatedLabel(context: context)
                .font(.system(size: 11))
                .foregroundStyle(context.isStale ? Color(.loopRed) : .white.opacity(0.7))
                .padding(.top, -2)

            Spacer(minLength: 0)

            Grid(horizontalSpacing: 1, verticalSpacing: -3) {
                GridRow {
                    Text(context.state.iob)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.insulin))
                        .gridColumnAlignment(.trailing)
                    Text("U")
                        .font(.system(size: 13).smallCaps())
                        .foregroundStyle(Color(.insulin))
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text(context.state.cob)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.loopYellow))
                    Text("g")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.loopYellow))
                }
            }
            .fontWidth(.condensed)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxHeight: .infinity)
    }

    private func glucoseDrop(_ state: LiveActivityAttributes.ContentState) -> some View {
        ZStack {
            let degree = dropAngle(state)
            let shadowDirection = direction(degree: degree)

            Image("SmallGlucoseDrops")
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
                    Text(decimalSeparator).font(.system(size: 18).weight(.semibold))
                    Text(decimal[1]).font(.system(size: 18))
                }
                .tracking(-1)
                .offset(x: -2)
                .foregroundColor(colorOfGlucose)
            } else {
                Text(string)
                    .font(Font.custom("SuggestionSmallPartsFontMgDl", fixedSize: 23).width(.condensed))
                    .foregroundColor(colorOfGlucose)
                    .offset(x: -2)
            }
        }
    }

    private func glucoseDisplayWatch(_ state: LiveActivityAttributes.ContentState) -> some View {
        HStack(alignment: .center, spacing: 6) {
            let string = state.bg
            let decimalSeparator =
                string.contains(decimalString) ? decimalString : "."

            let decimal = string.components(separatedBy: decimalSeparator)
            if decimal.count > 1 {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(decimal[0]).font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text(decimalSeparator).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(decimal[1]).font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                .foregroundColor(colorOfGlucose)
            } else {
                Text(string)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(colorOfGlucose)
            }

            if let direction = state.direction {
                Text(direction)
                    .font(.system(size: 16))
                    .foregroundColor(colorOfGlucose)
            }
        }
    }

    private var colorOfGlucose: Color {
        Color.white
    }

    private func limitedPredictions(
        _ predictions: LiveActivityAttributes.ActivityPredictions?,
        to count: Int
    ) -> LiveActivityAttributes.ActivityPredictions? {
        guard let predictions else { return nil }
        func limit(_ series: LiveActivityAttributes.ValueSeries?) -> LiveActivityAttributes.ValueSeries? {
            guard let series else { return nil }
            return .init(dates: Array(series.dates.prefix(count)), values: Array(series.values.prefix(count)))
        }
        return .init(
            iob: limit(predictions.iob),
            zt: limit(predictions.zt),
            cob: limit(predictions.cob),
            uam: limit(predictions.uam)
        )
    }

    private func maxOptional<T: Comparable>(_ values: T?...) -> T? {
        values.compactMap { $0 }.max()
    }

    private func minOptional<T: Comparable>(_ values: T?...) -> T? {
        values.compactMap { $0 }.min()
    }

    private func maxOptional1<T: Comparable>(_ first: T, _ values: T?...) -> T {
        values.compactMap { $0 }.max().map { max($0, first) } ?? first
    }

    private func minOptional1<T: Comparable>(_ first: T, _ values: T?...) -> T {
        values.compactMap { $0 }.min().map { min($0, first) } ?? first
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

    private func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        let text = Text("\(dateFormatter.string(from: context.state.loopDate))")
        return text
    }

    func displayValues(_ values: [Int16], conversion: Double) -> [Double] {
        values.map { Double($0) * conversion }
    }

    func makePoints(_ dates: [Date], _ values: [Int16], conversion: Double) -> [(date: Date, value: Double)] {
        zip(dates, displayValues(values, conversion: conversion)).map { ($0, $1) }
    }
}

private extension View {
    @ViewBuilder func applyingChartXScale(domain: ClosedRange<Date>?) -> some View {
        if let domain {
            chartXScale(domain: domain)
        } else {
            self
        }
    }
}
