import Charts
import SwiftUI

struct ActiveIOBView: View {
    @Binding var data: [IOBData]
    @Binding var neg: Int
    @Binding var tddChange: Decimal

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.negativePrefix = formatter.minusSign
        formatter.positivePrefix = formatter.plusSign
        return formatter
    }

    var body: some View {
        VStack {
            Text("Active Insulin").font(.previewHeadline).padding(.top, 20)
            iobView().frame(maxHeight: 200).padding(.horizontal, 20)
            sumView().frame(maxHeight: 100).padding(.vertical, 20)
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
                variable: NSLocalizedString("TDD compared to yesterday", comment: ""),
                formula: NSLocalizedString(" U", comment: ""),
                insulin: tddChange,
                color: Color(.insulin)
            )
        ]

        Grid {
            ForEach(tddChange == 0 ? entries.dropLast() : entries) { entry in
                GridRow(alignment: .firstTextBaseline) {
                    Text(entry.variable).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("")
                    Text((formatter.string(for: entry.insulin) ?? "") + entry.formula)
                        .bold(entry == entries.first).foregroundStyle(entry.color)
                }
            }
        }
        .padding(.horizontal, 20)
    }
}
