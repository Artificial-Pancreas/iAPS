
import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]

    var body: some View {
        Chart {
            ForEach(summaries, id: \.date) { item in
                // kcal als Balken
                BarMark(
                    x: .value("Date", item.date),
                    y: .value("kcal", item.kcal)
                )
                .foregroundStyle(.orange.opacity(0.5))

                // Carbs
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Carbs (g)", item.carbs)
                )
                .foregroundStyle(.blue)
                .interpolationMethod(.catmullRom)

                // Fat
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Fat (g)", item.fat)
                )
                .foregroundStyle(.red)
                .interpolationMethod(.catmullRom)

                // Protein
                LineMark(
                    x: .value("Date", item.date),
                    y: .value("Protein (g)", item.protein)
                )
                .foregroundStyle(.green)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 260)
    }
}
