import Charts
import Foundation
import SwiftUI

struct IllustrationView: View {
    @Binding var data: [InsulinRequired]

    @Environment(\.colorScheme) var colorScheme

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.negativePrefix = formatter.minusSign
        return formatter
    }

    private var barFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.negativePrefix = formatter.minusSign
        return formatter
    }

    var body: some View {
        // Data
        let chartdata = data.dropLast()
        // Range
        let minimum: Decimal = (chartdata.map(\.amount).min() ?? 0)
        let maximum: Decimal = (chartdata.map(\.amount).max() ?? 0)

        Chart(chartdata) { datapoint in
            BarMark(
                x: .value("Agent", datapoint.agent),
                y: .value("Amount", datapoint.amount),
                width: 30
            )
            .foregroundStyle(by: .value("Agent", datapoint.agent))
            .cornerRadius(2)
            RuleMark(y: .value("Zero", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3])).foregroundStyle(.gray)

            // Display all agents, even when amount == 0
            RectangleMark(
                x: .value("Agent", datapoint.agent),
                y: .value("Amount", datapoint.amount),
                width: 30,
                height: 2
            ).foregroundStyle(by: .value("Agent", datapoint.agent))
        }
        .chartForegroundStyleScale(
            [
                NSLocalizedString("Carbs", comment: ""): Color(.loopYellow),
                NSLocalizedString("IOB", comment: ""): Color(.insulin),
                NSLocalizedString("Glucose", comment: ""): Color(.loopGreen),
                NSLocalizedString("Trend", comment: ""): Color(.purple),
                NSLocalizedString("Factors", comment: ""): .gray,
                "": .clear
            ]
        )
        .dynamicTypeSize(...DynamicTypeSize.large)
        .chartYAxisLabel(NSLocalizedString("Insulin", comment: "Insulin unit"))
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(position: .bottom) { _ in
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden)
        .frame(maxWidth: UIScreen.main.bounds.width, maxHeight: UIScreen.main.bounds.height * 0.15)
        .padding(20)
        .chartYScale(
            domain: minimum * 1.1 ... maximum
        )

        // A very descriptive chart legend
        BolusLegend()
            .padding(.top, 10)
    }

    @ViewBuilder private func BolusLegend() -> some View {
        let entries = [
            BolusSummary(
                variable: NSLocalizedString("Carbs", comment: ""),
                formula: "COB / CR",
                insulin: data[0].amount,
                color: Color(.loopYellow)
            ),
            BolusSummary(
                variable: NSLocalizedString("IOB", comment: ""),
                formula: "- Active Insulin",
                insulin: data[1].amount,
                color: Color(.insulin)
            ),
            BolusSummary(
                variable: NSLocalizedString("Glucose", comment: ""),
                formula: "(BG - Target) / ISF",
                insulin: data[2].amount,
                color: Color(.loopGreen)
            ),
            BolusSummary(
                variable: NSLocalizedString("Trend", comment: ""),
                formula: "15 min delta / ISF",
                insulin: data[3].amount,
                color: .purple
            ),
            BolusSummary(
                variable: NSLocalizedString("Factors", comment: ""),
                formula: "Ev. adjustments",
                insulin: data[4].amount,
                color: .gray
            ),
            BolusSummary(
                variable: "",
                formula: "",
                insulin: data[5].amount,
                color: .primary
            )
        ]

        Grid {
            ForEach(entries) { entry in
                GridRow {
                    Text(entry.variable).foregroundStyle(entry.color).bold()
                    if entry != entries.last {
                        Text(entry.formula).foregroundStyle(.secondary).italic()
                        Text(formatter.string(for: entry.insulin) ?? "")
                    } else {
                        Text(entry.formula)
                        Text((formatter.string(for: entry.insulin) ?? "") + NSLocalizedString(" U", comment: "Insulin unit"))
                            .font(.title3).bold().foregroundStyle(.blue)
                    }
                }

                if entry != entries.last {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 20)
        .dynamicTypeSize(...DynamicTypeSize.small)
    }
}

// Live Preview
#Preview {
    // Preview data
    @State var testData = [
        InsulinRequired(agent: "Carbs", amount: 2),
        InsulinRequired(agent: "IOB", amount: -0.5),
        InsulinRequired(agent: "Glucose", amount: -0.5),
        InsulinRequired(agent: "Trend", amount: 0.4),
        InsulinRequired(agent: "Factors", amount: -1.0),
        InsulinRequired(agent: "Total", amount: 1.05)
    ]
    return IllustrationView(data: $testData)
}
