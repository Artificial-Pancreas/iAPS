import Charts
import SwiftUI

struct MealsMacrosChartView: View {
    let summaries: [MealDaySummary]

    // Hilfsstruktur für einzelne Balken (Carbs/Fat/Protein)
    struct MacroPoint: Identifiable {
        let id = UUID()
        let dayLabel: String // z.B. "16.02."
        let macro: String // "Carbs", "Fat", "Protein"
        let kcal: Double
        let color: Color
    }

    // Datum → String "dd.MM."
    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "dd.MM."
        return df
    }()

    // Alle Punkte für den Chart aufbereiten
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
                        color: .red
                    )
                )
            }

            if item.fat > 0 {
                result.append(
                    MacroPoint(
                        dayLabel: label,
                        macro: "Fat",
                        kcal: item.fat * 9.0,
                        color: .blue
                    )
                )
            }

            if item.protein > 0 {
                result.append(
                    MacroPoint(
                        dayLabel: label,
                        macro: "Protein",
                        kcal: item.protein * 4.0,
                        color: .green
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
        .chartYAxisLabel("kcal")
        .frame(height: 260)
    }
}
