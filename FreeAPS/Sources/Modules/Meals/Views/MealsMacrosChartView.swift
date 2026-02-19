import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]
    let range: MealsRange

    @Environment(\.colorScheme) private var colorScheme

    struct MacroPoint: Identifiable {
        let id = UUID()
        let dayLabel: String
        let macro: String
        let kcal: Double
        let color: Color
    }

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        // Hier ist das neue Format: TT.MM.YY
        df.dateFormat = "dd.MM.yy"
        return df
    }()

    // MARK: - Adaptive Colors

    private var carbsColor: Color {
        colorScheme == .dark ? .red : Color(red: 0.8, green: 0.0, blue: 0.0)
    }

    private var fatColor: Color {
        colorScheme == .dark ? .blue : Color(red: 0.0, green: 0.4, blue: 0.9)
    }

    private var proteinColor: Color {
        colorScheme == .dark ? .green : Color(red: 0.0, green: 0.6, blue: 0.2)
    }

    var points: [MacroPoint] {
        summaries.flatMap { item -> [MacroPoint] in
            guard item.kcal > 0 else { return [] }

            let day = Calendar.current.startOfDay(for: item.date)
            let label = MealsMacrosChartView.dayFormatter.string(from: day)

            var result: [MacroPoint] = []

            if item.carbs > 0 {
                result.append(
                    MacroPoint(
                        dayLabel: label,
                        macro: "Carbs",
                        kcal: item.carbs * 4.0,
                        color: carbsColor
                    )
                )
            }

            if item.fat > 0 {
                result.append(
                    MacroPoint(
                        dayLabel: label,
                        macro: "Fat",
                        kcal: item.fat * 9.0,
                        color: fatColor
                    )
                )
            }

            if item.protein > 0 {
                result.append(
                    MacroPoint(
                        dayLabel: label,
                        macro: "Protein",
                        kcal: item.protein * 4.0,
                        color: proteinColor
                    )
                )
            }

            return result
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.dayLabel),
                    y: .value("kcal", point.kcal)
                )
                .foregroundStyle(point.color)
            }
        }
        .chartXAxis {
            if range == .oneWeek {
                AxisMarks()
            } else {
                AxisMarks {
                    AxisValueLabel("")
                }
            }
        }
        .chartYAxisLabel("kcal")
        .frame(height: 260)
    }
}
