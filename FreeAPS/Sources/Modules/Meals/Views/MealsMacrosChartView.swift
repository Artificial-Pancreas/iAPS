import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]

    var body: some View {
        Chart {
            ForEach(summaries, id: \.id) { item in
                if item.kcal > 0 {
                    if item.carbs > 0 {
                        BarMark(
                            x: .value("Date", item.date),
                            y: .value("Energy (kcal)", item.carbs * 4.0)
                        )
                        .foregroundStyle(.red)
                    }

                    if item.fat > 0 {
                        BarMark(
                            x: .value("Date", item.date),
                            y: .value("Energy (kcal)", item.fat * 9.0)
                        )
                        .foregroundStyle(.blue)
                    }

                    if item.protein > 0 {
                        BarMark(
                            x: .value("Date", item.date),
                            y: .value("Energy (kcal)", item.protein * 4.0)
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
        }
        .frame(height: 260)
    }
}
