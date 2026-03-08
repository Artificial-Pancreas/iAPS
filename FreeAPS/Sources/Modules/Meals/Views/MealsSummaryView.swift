import SwiftUI

struct MealsSummaryView: View {
    @Binding var data: MealData

    @Environment(\.colorScheme) private var colorScheme

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.negativePrefix = formatter.minusSign
        formatter.positivePrefix = formatter.plusSign
        return formatter
    }

    private var tddFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var intFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    // MARK: - Adaptive Colors

    private var kcalColor: Color {
        colorScheme == .dark ? .orange : Color(red: 0.9, green: 0.5, blue: 0.0)
    }

    private var carbsColor: Color {
        colorScheme == .dark ? .red : Color(red: 0.8, green: 0.0, blue: 0.0)
    }

    private var fatColor: Color {
        colorScheme == .dark ? .blue : Color(red: 0.0, green: 0.4, blue: 0.9)
    }

    private var proteinColor: Color {
        colorScheme == .dark ? .green : Color(red: 0.0, green: 0.6, blue: 0.2)
    }

    // Neue Farbe für Servings hinzugefügt
    private var servingsColor: Color {
        colorScheme == .dark ? .purple : Color(red: 0.5, green: 0.1, blue: 0.7)
    }

    var body: some View {
        VStack {
            Text("Today's Meals")
                .font(.previewHeadline)
                .padding(.top, 20)
                .padding(.bottom, 15)

            servingsView
                .padding(.horizontal, 23)

            caloriesView
                .padding(.horizontal, 23)

            nutrientsView
                .padding(.horizontal, 23)
                .padding(.bottom, 10)
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var caloriesView: some View {
        let kcal = data.kcal

        return HStack {
            Text("Kilo Calories")
                .foregroundColor(kcalColor)
            Spacer()
            Text(intFormatter.string(from: kcal as NSNumber) ?? "")
                .foregroundColor(kcalColor)
        }
    }

    private var servingsView: some View {
        let servings = data.servings

        return HStack {
            Text("Servings")
                .foregroundColor(servingsColor)
            Spacer()
            Text(intFormatter.string(from: servings as NSNumber) ?? "")
                .foregroundColor(servingsColor)
        }
    }

    private var nutrientsView: some View {
        VStack {
            if data.carbs > 0 {
                HStack {
                    Text("Carbs")
                        .foregroundColor(carbsColor)
                    Spacer()
                    Text(intFormatter.string(from: data.carbs as NSNumber) ?? "")
                        .foregroundColor(carbsColor)
                    Text("g")
                        .foregroundColor(carbsColor)
                }
            }

            if data.fat > 0 {
                HStack {
                    Text("Fat")
                        .foregroundColor(fatColor)
                    Spacer()
                    Text(intFormatter.string(from: data.fat as NSNumber) ?? "")
                        .foregroundColor(fatColor)
                    Text("g")
                        .foregroundColor(fatColor)
                }
            }

            if data.protein > 0 {
                HStack {
                    Text("Protein")
                        .foregroundColor(proteinColor)
                    Spacer()
                    Text(intFormatter.string(from: data.protein as NSNumber) ?? "")
                        .foregroundColor(proteinColor)
                    Text("g")
                        .foregroundColor(proteinColor)
                }
            }
        }
    }
}
