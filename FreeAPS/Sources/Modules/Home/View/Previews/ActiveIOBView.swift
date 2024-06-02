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
            Text("Active Insulin").font(.previewHeadline).padding(.top, 20)
            iobView().frame(maxHeight: 200).padding(.horizontal, 20)
            sumView().frame(maxHeight: 250).padding(.vertical, 30)
        }.dynamicTypeSize(...DynamicTypeSize.medium)
    }

    @ViewBuilder private func iobView() -> some View {
        let minimum = data.map(\.iob).min() ?? 0
        let minimumRange = min(0, minimum * 1.3)
        let maximum = (data.map(\.iob).max() ?? 0) * 1.1

        Chart(data) {
            AreaMark(
                x: .value("Time", $0.date),
                y: .value("IOB", $0.iob)
            ).foregroundStyle(Color(.insulin))
        }
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
            domain: minimumRange ... maximum
        )
        .chartXScale(
            domain: Date.now.addingTimeInterval(-1.days.timeInterval) ... Date.now
        )
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
                variable: NSLocalizedString("Average Insulin past 24h", comment: ""),
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
}
