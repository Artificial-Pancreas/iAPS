import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityChart: View {
    let context: ActivityViewContext<LiveActivityAttributes>
    var isWatch: Bool = false

    private let dropWidth = CGFloat(80)
    private let dropHeight = CGFloat(80)

    private let decimalString: String = Locale.current.decimalSeparator ?? "."

    private let glucoseColor = Color.white

    var body: some View {
        if isWatch {
            watchBody
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        HStack(alignment: .top) {
            chartView
                .padding(.bottom, 10)
                .padding(.top, 30)
                .padding(.leading, 15)
                .padding(.trailing, 10)
                .background(.black.opacity(0.30))

            VStack(alignment: .trailing, spacing: 0) {
                chartRightHandView
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 15)
            .padding(.trailing, 15)
        }
        .overlay {
            timeAndEventualOverlay
        }
        .foregroundStyle(.white)
        .privacySensitive()
        .padding(0)
        .background(Color.black.opacity(0.6))
        .activityBackgroundTint(Color.clear)
    }

    private var watchBody: some View {
        VStack(spacing: 0) {
            watchTopRow
            chartView
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .overlay(alignment: .bottomLeading) {
            WatchLoopCircleAndTimestamp(context: context)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                .padding(.leading, 5)
                .padding(.bottom, 5)
        }
        .overlay(alignment: .bottomTrailing) {
            BannerEventualGlucose(context: context)
                .font(.system(size: 16))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                .padding(.trailing, 5)
                .padding(.bottom, 5)
        }
        .foregroundStyle(.white)
        .privacySensitive()
        .padding(0)
        .background(Color.black)
        .activityBackgroundTint(Color.black)
    }

    private var watchTopRow: some View {
        HStack(alignment: .center) {
            WatchIOBCOBDisplay(context: context)
            Spacer()
            WatchGlucoseDisplay(context: context)
        }
    }

    private var chartView: some View {
        let state = context.state
        let conversionConstant: Double = (state.mmol ? 0.0555 : 1)

        // on the watch, we display only up to 10 prediction points
        let predictions = isWatch ? limitedPredictions(state.predictions, to: 10) : state.predictions

        // Prediction data
        let iob: [Int16] = predictions?.iob?.values ?? []
        let cob: [Int16] = predictions?.cob?.values ?? []
        let zt: [Int16] = predictions?.zt?.values ?? []
        let uam: [Int16] = predictions?.uam?.values ?? []

        // Prepare for domain range
        let lowThreshold = Double(state.chartLowThreshold) * conversionConstant
        let highThreshold = Double(state.chartHighThreshold) * conversionConstant

        // Min/max BG values
        let minValue = state.readings?.values.min().map({ Double($0) * conversionConstant })
        let maxValue = state.readings?.values.max().map({ Double($0) * conversionConstant })

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

        // Min/max Prediction values
        let maxPrediction = maxOptional(
            iob.max(), cob.max(), zt.max(), uam.max()
        ).map({ Double($0) * conversionConstant })

        let minPrediction = minOptional(
            iob.max(), cob.max(), zt.max(), uam.max()
        ).map({ Double($0) * conversionConstant })

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
            max(yDomainMin, 0) ... min(yDomainMax, 400 * conversionConstant)
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
            makePoints($0.dates, $0.values, conversion: conversionConstant)
        })
        let iobPoints = predictions?.iob.map({ makePoints($0.dates, $0.values, conversion: conversionConstant) })
        let ztPoints = predictions?.zt.map({ makePoints($0.dates, $0.values, conversion: conversionConstant) })
        let cobPoints = predictions?.cob.map({ makePoints($0.dates, $0.values, conversion: conversionConstant) })
        let uamPoints = predictions?.uam.map({ makePoints($0.dates, $0.values, conversion: conversionConstant) })

        let nowDate = Date()
        let xScaleEnd: Date = isWatch ? max(xEnd ?? nowDate, nowDate.addingTimeInterval(80 * 60)) : (xEnd ?? nowDate)

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
            if !isWatch, let minValue, let maxValue {
                AxisMarks(
                    position: .leading,
                    values: abs(maxValue - minValue) < 0.8 ? [
                        (maxValue + minValue) / 2
                    ] : [
                        minValue,
                        maxValue
                    ]
                ) { _ in
                    AxisValueLabel(format: glucoseFormatter, horizontalSpacing: 10)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .applyingChartXScale(domain: isWatch ? xStart.map { $0 ... xScaleEnd } : nil)
    }

    @ViewBuilder private var chartRightHandView: some View {
        glucoseDrop
            .offset(y: -7)
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

    @ViewBuilder private var timeAndEventualOverlay: some View {
        BannerEventualGlucose(context: context)
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 10)
            .padding(.trailing, 110)

        BannerTimestampLabel(context: context)
            .font(.system(size: 11))
            .foregroundStyle(context.isStale ? Color(.loopRed) : .white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 10).padding(.leading, 50)
    }

    private var glucoseDrop: some View {
        ZStack {
            let degree = dropAngle
            let shadowDirection = direction(degree: degree)

            Image("SmallGlucoseDrops")
                .resizable()
                .frame(width: dropWidth, height: dropHeight).rotationEffect(.degrees(degree))
                .animation(.bouncy(duration: 1, extraBounce: 0.2), value: degree)
                .shadow(radius: 3, x: shadowDirection.x, y: shadowDirection.y)

            let string = context.state.bg
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
                .foregroundStyle(glucoseColor)
            } else {
                Text(string)
                    .font(Font.custom("SuggestionSmallPartsFontMgDl", fixedSize: 23).width(.condensed))
                    .foregroundStyle(glucoseColor)
                    .offset(x: -2)
            }
        }
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

    private var dropAngle: Double {
        guard let direction = context.state.direction else {
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

    private func displayValues(_ values: [Int16], conversion: Double) -> [Double] {
        values.map { Double($0) * conversion }
    }

    private func makePoints(_ dates: [Date], _ values: [Int16], conversion: Double) -> [(date: Date, value: Double)] {
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
