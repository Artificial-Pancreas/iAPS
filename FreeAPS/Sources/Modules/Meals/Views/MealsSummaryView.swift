import SwiftUI

struct MealsSummaryView: View {
    @Binding var data: MealData

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

    var body: some View {
        VStack {
            Text("Today's Meals").font(.previewHeadline).padding(.top, 20).padding(.bottom, 15)
            servingsView.padding(.horizontal, 23)
            caloriesView.padding(.horizontal, 23)
            nutrientsView.padding(.horizontal, 23).padding(.bottom, 10)
        }.dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var caloriesView: some View {
        let kcal = data.kcal
        return HStack {
            Text("Kilo Calories")
            Spacer()
            Text(intFormatter.string(from: kcal as NSNumber) ?? "")
        }.foregroundStyle(.secondary)
    }

    private var servingsView: some View {
        let servings = data.servings
        return HStack {
            Text("Servings")
            Spacer()
            Text(intFormatter.string(from: servings as NSNumber) ?? "")
        }.foregroundStyle(.secondary)
    }

    private var nutrientsView: some View {
        VStack {
            if data.carbs > 0 {
                HStack {
                    Text("Carbs")
                    Spacer()
                    Text(intFormatter.string(from: data.carbs as NSNumber) ?? "")
                    Text("g")
                }
            }

            if data.fat > 0 {
                HStack {
                    Text("Fat")
                    Spacer()
                    Text(intFormatter.string(from: data.fat as NSNumber) ?? "")
                    Text("g")
                }
            }

            if data.protein > 0 {
                HStack {
                    Text("Protein")
                    Spacer()
                    Text(intFormatter.string(from: data.protein as NSNumber) ?? "")
                    Text("g")
                }
            }
        }.foregroundStyle(.secondary)
    }
}
