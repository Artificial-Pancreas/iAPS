import SwiftUI

struct AIAnalysisResultsView: View {
    let analysisResult: AIFoodAnalysisResult
    let onFoodItemSelected: (FoodItem) -> Void
    let onCompleteMealSelected: (FoodItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header mit Gesamtübersicht
            VStack(alignment: .leading, spacing: 12) {
                Text("🧠 AI food analysis")
                    .font(.title2)
                    .fontWeight(.bold)

                if let description = analysisResult.overallDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Konfidenz-Level
                HStack {
                    Text("Confidence:")
                    ConfidenceBadge(level: analysisResult.confidence)
                    Spacer()
                    if let portions = analysisResult.totalFoodPortions {
                        Text("\(portions) Portionen")
                            .font(.caption)
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal)

            // Gesamt-Nährwerte der Mahlzeit
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("📊 Total nutritional values of the meal")
                        .font(.headline)

                    Spacer()

                    // ERWEITERTER Gesamtmahlzeit-Button (HIER EINFÜGEN)
                    Button(action: {
                        let mealName = analysisResult.foodItemsDetailed.count == 1 ?
                            analysisResult.foodItemsDetailed.first?.name ?? "Meal" :
                            "Complete Meal"

                        let totalMeal = FoodItem(
                            name: mealName,
                            carbs: Decimal(analysisResult.totalCarbohydrates),
                            fat: Decimal(analysisResult.totalFat ?? 0),
                            protein: Decimal(analysisResult.totalProtein ?? 0),
                            source: "AI food analysis • \(analysisResult.foodItemsDetailed.count) Food"
                        )
                        onCompleteMealSelected(totalMeal)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gesamt hinzufügen")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(analysisResult.foodItemsDetailed.count) Lebensmittel")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                    NutritionSummaryBadge(
                        value: analysisResult.totalCarbohydrates,
                        unit: "g",
                        label: "Kohlenhydrate",
                        color: .blue
                    )

                    if let protein = analysisResult.totalProtein {
                        NutritionSummaryBadge(value: protein, unit: "g", label: "Protein", color: .green)
                    }

                    if let fat = analysisResult.totalFat {
                        NutritionSummaryBadge(value: fat, unit: "g", label: "Fett", color: .orange)
                    }

                    if let fiber = analysisResult.totalFiber {
                        NutritionSummaryBadge(value: fiber, unit: "g", label: "Ballaststoffe", color: .purple)
                    }

                    if let calories = analysisResult.totalCalories {
                        NutritionSummaryBadge(value: calories, unit: "kcal", label: "Kalorien", color: .red)
                    }

                    if let servings = analysisResult.totalUsdaServings {
                        NutritionSummaryBadge(value: servings, unit: "", label: "USDA Portionen", color: .indigo)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // Einzelne Lebensmittel
            Text("🍽️ Einzelne Lebensmittel")
                .font(.headline)
                .padding(.horizontal)

            ForEach(analysisResult.foodItemsDetailed, id: \.name) { foodItem in
                FoodItemCard(
                    foodItem: foodItem,
                    onSelect: {
                        let selectedFood = FoodItem(
                            name: foodItem.name,
                            carbs: Decimal(foodItem.carbohydrates),
                            fat: Decimal(foodItem.fat ?? 0),
                            protein: Decimal(foodItem.protein ?? 0),
                            source: "AI Analyse"
                        )
                        onFoodItemSelected(selectedFood)
                    }
                )
            }

            // Diabetes-spezifische Empfehlungen
            if let diabetesInfo = analysisResult.diabetesConsiderations {
                VStack(alignment: .leading, spacing: 8) {
                    Label("💉 Diabetes Empfehlungen", systemImage: "cross.case.fill")
                        .font(.headline)
                    Text(diabetesInfo)
                        .font(.subheadline)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            // Zusätzliche Hinweise
            if let notes = analysisResult.notes {
                VStack(alignment: .leading, spacing: 8) {
                    Label("📝 Hinweise", systemImage: "note.text")
                        .font(.headline)
                    Text(notes)
                        .font(.subheadline)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
}
