import CoreData
import SwiftUI

struct MealsSummaryView: View {
    @FetchRequest(
        entity: Meals.entity(),
        sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate:
        NSPredicate(format: "actualDate > %@", DateFilter().day)
    ) var fetchedMeals: FetchedResults<Meals>

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
            Text("Meals").font(.previewHeadline).padding(.top, 20).padding(.bottom, 15)
            servingsView.padding(.horizontal, 23)
            caloriesView.padding(.horizontal, 23)
            nutrientsView.padding(.horizontal, 23).padding(.bottom, 10)
        }.dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    private var caloriesView: some View {
        let kcal = kcal()
        return HStack {
            Text("Kilo Calories")
            Spacer()
            Text(intFormatter.string(from: kcal as NSNumber) ?? "")
        }.foregroundStyle(.secondary)
    }

    private var servingsView: some View {
        let servings = servings
        return HStack {
            Text("Servings")
            Spacer()
            Text(intFormatter.string(from: servings as NSNumber) ?? "")
        }.foregroundStyle(.secondary)
    }

    private var nutrientsView: some View {
        VStack {
            if carbs > 0 {
                HStack {
                    Text("Carbs")
                    Spacer()
                    Text(intFormatter.string(from: carbs as NSNumber) ?? "")
                    Text("g")
                }
            }

            if fat > 0 {
                HStack {
                    Text("Fat")
                    Spacer()
                    Text(intFormatter.string(from: fat as NSNumber) ?? "")
                    Text("g")
                }
            }

            if protein > 0 {
                HStack {
                    Text("Protein")
                    Spacer()
                    Text(intFormatter.string(from: protein as NSNumber) ?? "")
                    Text("g")
                }
            }
        }.foregroundStyle(.secondary)
    }

    private var carbs: Double {
        fetchedMeals.map(\.carbs).reduce(0, +)
    }

    private var fat: Double {
        fetchedMeals.map(\.fat).reduce(0, +)
    }

    private var protein: Double {
        fetchedMeals.map(\.protein).reduce(0, +)
    }

    private var servings: Int {
        fetchedMeals.count
    }

    private func kcal() -> Double {
        4 * (carbs + protein) + fat * 9
    }
}
