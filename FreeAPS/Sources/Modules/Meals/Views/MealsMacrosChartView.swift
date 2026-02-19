import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]

    var body: some View {
        Chart {
            ForEach(summaries, id: \.id) { item in
                let day = Calendar.current.startOfDay(for: item.date)

                if item.kcal > 0 {
                    if item.carbs > 0 {
                        BarMark(
                            x: .value("Date", day),
                            y: .value("Energy (kcal)", item.carbs * 4.0)
                        )
                        .foregroundStyle(.red)
                    }

                    if item.fat > 0 {
                        BarMark(
                            x: .value("Date", day),
                            y: .value("Energy (kcal)", item.fat * 9.0)
                        )
                        .foregroundStyle(.blue)
                    }

                    if item.protein > 0 {
                        BarMark(
                            x: .value("Date", day),
                            y: .value("Energy (kcal)", item.protein * 4.0)
                        )
                        .foregroundStyle(.green)
                    }
                }
            }
        }
        // Domain etwas enger, damit die Balken dicker wirken
        .chartXScale(domain: computeDomain())
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.day().month(.twoDigits))
                    }
                }
            }
        }
        .frame(height: 260)
    }

    private func computeDomain() -> ClosedRange<Date> {
        let days = summaries
            .map { Calendar.current.startOfDay(for: $0.date) }
            .sorted()

        guard let first = days.first, let last = days.last else {
            let today = Calendar.current.startOfDay(for: Date())
            return today ... today
        }

        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -1, to: first) ?? first
        let end = cal.date(byAdding: .day, value: 1, to: last) ?? last
        return start ... end
    }
}
