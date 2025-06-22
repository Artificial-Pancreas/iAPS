import ActivityKit
import Charts
import Foundation
import SwiftUI
import WidgetKit

struct LiveActivityChart: View {
    let context: ActivityViewContext<LiveActivityAttributes>

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
            .frame(maxHeight: .infinity)
            .padding(.top, 15)
            .padding(.bottom, 15)
            .padding(.trailing, 15)
        }
        .foregroundStyle(.white)
        .overlay {
            ZStack {
                timeAndEventualOverlay(for: context)
            }
        }
        .privacySensitive()
        .padding(0)
        .background(Color.black.opacity(0.6))
        .activityBackgroundTint(Color.clear)
    }

    private func chartView(for state: LiveActivityAttributes.ContentState) -> some View {
        let ConversionConstant: Double = (state.mmol ? 0.0555 : 1)

        // Prediction data
        let iob: [Int16] = state.predictions?.iob?.values ?? []
        let cob: [Int16] = state.predictions?.cob?.values ?? []
        let zt: [Int16] = state.predictions?.zt?.values ?? []
        let uam: [Int16] = state.predictions?.uam?.values ?? []

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
            state.predictions?.iob?.dates.max(),
            state.predictions?.cob?.dates.max(),
            state.predictions?.zt?.dates.max(),
            state.predictions?.uam?.dates.max(),
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
        let iobPoints = state.predictions?.iob.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })
        let ztPoints = state.predictions?.zt.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })
        let cobPoints = state.predictions?.cob.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })
        let uamPoints = state.predictions?.uam.map({ makePoints($0.dates, $0.values, conversion: ConversionConstant) })

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

            if let xStart = xStart, let xEnd = xEnd {
                RectangleMark(
                    xStart: .value("Start", xStart),
                    xEnd: .value("End", xEnd),
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
                AxisValueLabel(format: .dateTime.hour())
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            if let minValue, let maxValue {
                AxisMarks(
                    position: .leading,
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
                        horizontalSpacing: 10
                    )
                    .foregroundStyle(.secondary)
                }
            }
        }
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

    private var colorOfGlucose: Color {
        Color.white
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
