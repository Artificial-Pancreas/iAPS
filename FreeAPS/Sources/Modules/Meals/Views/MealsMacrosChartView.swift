import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]

    var body: some View {
        Chart {
            // each summary is one day
            ForEach(summaries, id: \.id) { item in
                if item.kcal > 0 {
                    // Carbs
                    if item.carbs > 0 {
                        BarMark(
                            x: .value("Date", item.date),
                            y: .value("Energy (kcal)", item.carbs * 4.0)
                        )
                        .foregroundStyle(.red)
                        .position(by: .value("Macro", "Carbs"))
                        .cornerRadius(2)
                    }

                    // Fat
                    if item.fat > 0 {
                        BarMark(
                            x: .value("Date", item.date),
                            y: .value("Energy (kcal)", item.fat * 9.0)
                        )
                        .foregroundStyle(.blue)
                        .position(by: .value("Macro", "Fat"))
                        .cornerRadius(2)
                    }

                    // Protein
                    if item.protein > 0 {
                        BarMark(
                            x: .value("Date", item.date),
                            y: .value("Energy (kcal)", item.protein * 4.0)
                        )
                        .foregroundStyle(.green)
                        .position(by: .value("Macro", "Protein"))
                        .cornerRadius(2)
                    }
                }
            }
        }
        // X axis: dates as TT.MM.
        .chartXAxis {
            AxisMarks(values: summaries.map(\.date)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.day().month(.twoDigits))
                    }
                }
            }
        }
        .chartXScale(domain: summaries.map(\.date))
        .frame(height: 260)
    }
}
