import Charts
import SwiftUI

struct ActiveIOBView: View {
    @Binding var data: [IOBData]
    @Binding var neg: Int
    @Binding var tddChange: Decimal
    @Binding var tddAverage: Decimal
    @Binding var tddYesterday: Decimal
    @Binding var tdd2DaysAgo: Decimal
    @Binding var tdd3DaysAgo: Decimal
    @Binding var tddActualAverage: Decimal

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
            Text("Active Insulin").font(.previewHeadline).padding(.top, 20).padding(.bottom, 15)
            iobView().frame(maxHeight: 130).padding(.horizontal, 20)
            sumView().frame(maxHeight: 250).padding(.top, 20).padding(.bottom, 10)
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

    @ViewBuilder private func sumView() -> some View {
        let entries = [
            BolusSummary(
                variable: NSLocalizedString("Time with negative insulin", comment: ""),
                formula: NSLocalizedString(" min", comment: ""),
                insulin: Decimal(neg),
                color: .red
            ),
            BolusSummary(
                variable: NSLocalizedString("Insulin compared to yesterday", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tddChange,
                color: Color(.insulin)
            ),
            BolusSummary(
                variable: NSLocalizedString("Insulin compared to average", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tddAverage,
                color: Color(.insulin)
            ),
            BolusSummary(
                variable: "",
                formula: "",
                insulin: .zero,
                color: Color(.clear)
            ),
            BolusSummary(
                variable: NSLocalizedString("Average Insulin 10 days", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tddActualAverage,
                color: .secondary
            ),
            BolusSummary(
                variable: "",
                formula: "",
                insulin: .zero,
                color: Color(.clear)
            ),
            BolusSummary(
                variable: NSLocalizedString("TDD yesterday", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tddYesterday,
                color: .secondary
            ),
            BolusSummary(
                variable: NSLocalizedString("TDD 2 days ago", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tdd2DaysAgo,
                color: .secondary
            ),
            BolusSummary(
                variable: NSLocalizedString("TDD 3 days ago", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tdd3DaysAgo,
                color: .secondary
            )
        ]

        let insulinData = useData(entries)

        Grid {
            ForEach(insulinData) { entry in

                GridRow(alignment: .firstTextBaseline) {
                    Text(entry.variable).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("")
                    if entry.insulin != 0 {
                        Text(
                            ((isTDD(entry.insulin) ? tddFormatter : formatter).string(for: entry.insulin) ?? "") + entry
                                .formula
                        )
                        .bold(entry == entries.first).foregroundStyle(entry.color)
                    } else if entry.variable != "" {
                        Text("0").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func isTDD(_ insulin: Decimal) -> Bool {
        insulin == tddYesterday || insulin == tdd2DaysAgo || insulin == tdd3DaysAgo || insulin == tddActualAverage
    }

    private func useData(_ data: [BolusSummary]) -> [BolusSummary] {
        if neg == 0 {
            return data.dropFirst().map({ a -> BolusSummary in a })
        }
        return data
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
