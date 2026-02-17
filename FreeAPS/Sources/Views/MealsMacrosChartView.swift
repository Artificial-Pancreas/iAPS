
import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]

    var body: some View {
        Chart {
            ForEach(summaries) { item in
                if item.kcal > 0 {
                    BarMark(
                        x: .value("Date", item.date),
                        y: .value("kcal", item.kcal)
                    )
                    .foregroundStyle(.orange.opacity(0.4))
                }

                if item.carbs > 0 {
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Carbs (g)", item.carbs)
                    )
                    .foregroundStyle(.blue)
                }

                if item.fat > 0 {
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Fat (g)", item.fat)
                    )
                    .foregroundStyle(.red)
                }

                if item.protein > 0 {
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Protein (g)", item.protein)
                    )
                    .foregroundStyle(.green)
                }
            }
        }
        .frame(height: 260)
    }
}
