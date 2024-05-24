import Charts
import SwiftUI

struct ActiveCOBView: View {
    @Binding var data: [IOBData]

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.negativePrefix = formatter.minusSign
        return formatter
    }

    var body: some View {
        VStack {
            Text("Active Carbohydrates").font(.previewHeadline).padding(.top, 20)
            cobView().frame(maxHeight: 150).padding(.vertical, 10).padding(.horizontal, 20)
                .padding(.bottom, 10)
        }.dynamicTypeSize(...DynamicTypeSize.medium)
    }

    @ViewBuilder private func cobView() -> some View {
        let maximum = max(0, (data.map(\.cob).max() ?? 0) * 1.1)

        Chart(data) {
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
                AxisValueLabel(
                    format: .dateTime.hour(.defaultDigits(amPM: .omitted))
                        .locale(Locale(identifier: "sv")) // Force 24h
                )
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
}
