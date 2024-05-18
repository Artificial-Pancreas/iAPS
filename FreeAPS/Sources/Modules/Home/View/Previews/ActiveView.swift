import Charts
import SwiftUI

struct ActiveView: View {
    @Binding var data: [IOBData]
    @Binding var neg: Int

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.negativePrefix = formatter.minusSign
        return formatter
    }

    var body: some View {
        VStack {
            Text("Active Carbohydrates").foregroundStyle(.secondary).padding(.top, 10)
            // Text("Test: \(data.first?.cob ?? 0)")
            cobView().frame(maxHeight: 100).padding(.vertical, 10)
            Text("Active Insulin").foregroundStyle(.secondary)
            // Text("Test: \(data.first?.iob ?? 0)")
            iobView().frame(maxHeight: 100)
            sumView().frame(maxHeight: 100).padding(.bottom, 10)
        }
    }

    @ViewBuilder private func cobView() -> some View {
        let maximum = max(0, (data.map(\.cob).max() ?? 0) * 1.1)

        Chart(data) { // datapoint in
            AreaMark(
                x: .value("Time", $0.date),
                y: .value("COB", $0.cob)
            ).foregroundStyle(Color(.loopYellow))
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisGridLine()
            }
        }
        .chartYScale(
            domain: 0 ... maximum
        )
        .chartXScale(
            domain: Date.now.addingTimeInterval(-1.days.timeInterval) ... Date.now
        )
    }

    @ViewBuilder private func iobView() -> some View {
        let minimum = min(0, (data.map(\.iob).min() ?? 0) * 1.2)
        let maximum = (data.map(\.iob).max() ?? 0) * 1.1

        Chart(data) { // datapoint in
            AreaMark(
                x: .value("Time", $0.date),
                y: .value("IOB", $0.iob)
            ).foregroundStyle(Color(.insulin))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .chartYScale(
            domain: minimum ... maximum
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
            )
        ]

        Grid {
            ForEach(entries) { entry in
                GridRow(alignment: .firstTextBaseline) {
                    Text(entry.variable).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("")
                    Text((formatter.string(for: entry.insulin) ?? "") + entry.formula)
                        .bold().foregroundStyle(entry.color)
                }
            }
        }
        .padding(.horizontal, 20)
        .dynamicTypeSize(...DynamicTypeSize.small)
    }
}
