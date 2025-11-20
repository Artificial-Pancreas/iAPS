import Charts
import SwiftUI

struct ActiveIOBView: View {
    @Binding var data: [IOBData]

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.negativePrefix = formatter.minusSign
        formatter.positivePrefix = formatter.plusSign
        return formatter
    }

    private var tddFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        VStack {
            Text("Insulin on Board").font(.previewHeadline).padding(.top, 20).padding(.bottom, 15)
            iobView().frame(maxHeight: 130).padding(.bottom, 10).padding(.horizontal, 20)
        }.dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder private func iobView() -> some View {
        // Data
        let negIOBData = negIOBdata(data)
        // Domain
        let minimum = min(data.map(\.iob).min() ?? 0, negIOBData.map(\.iob).min() ?? 0)
        let minimumRange = min(0, minimum * 1.3)
        let maximum = (data.map(\.iob).max() ?? 0) * 1.1

        Chart {
            ForEach(data) { item in
                LineMark(
                    x: .value("Time", item.date),
                    y: .value("IOB", item.iob)
                ).foregroundStyle(by: .value("Time", "Line IOB > 0"))
                    .lineStyle(StrokeStyle(lineWidth: 0.8))

                AreaMark(
                    x: .value("Time", item.date),
                    y: .value("IOB", item.iob)
                ).foregroundStyle(by: .value("Time", "IOB > 0"))
            }
            ForEach(negIOBData) { item in
                AreaMark(
                    x: .value("Time", item.date),
                    yStart: .value("IOB", 0),
                    yEnd: .value("IOB", item.iob)
                ).foregroundStyle(by: .value("Time", "IOB < 0"))
            }
        }
        .chartForegroundStyleScale(
            [
                "IOB > 0": LinearGradient(
                    gradient: Gradient(colors: [
                        Color.insulin.opacity(1),
                        Color.insulin.opacity(0.4)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ),
                "IOB < 0": LinearGradient(
                    gradient: Gradient(colors: [
                        Color.red.opacity(1),
                        Color.red.opacity(1)
                    ]),
                    startPoint: .bottom,
                    endPoint: .top
                ),
                "Line IOB > 0": LinearGradient(
                    gradient: Gradient(colors: [
                        Color.insulin.opacity(1),
                        Color.insulin.opacity(1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            ]
        )
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel(
                    format: .dateTime.hour(.defaultDigits(amPM: .omitted))
                        .locale(Locale(identifier: "sv")) // Force 24h. Not pretty.
                )
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .chartYScale(
            domain: minimumRange ... max(minimumRange, maximum, minimumRange + 1)
        )
        .chartXScale(
            domain: Date.now.addingTimeInterval(-1.days.timeInterval) ... Date.now
        )
        .chartLegend(.hidden)
    }

    private func negIOBdata(_ data: [IOBData]) -> [IOBData] {
        var array = [IOBData]()
        var previous = data.first
        for item in data {
            if item.iob < 0 {
                if previous?.iob ?? 0 >= 0 {
                    array.append(IOBData(date: previous?.date ?? .distantPast, iob: 0, cob: 0))
                }
                array.append(IOBData(date: item.date, iob: item.iob, cob: 0))
            } else if previous?.iob ?? 0 < 0 {
                array.append(IOBData(date: item.date, iob: 0, cob: 0))
            }
            previous = item
        }
        return array
    }
}
