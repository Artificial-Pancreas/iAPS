import SwiftUI

struct AIAnalysisResultsView: View {
    let analysisResult: AIFoodAnalysisResult
    let onFoodItemSelected: (FoodItem) -> Void
    let onCompleteMealSelected: (FoodItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("🧠 AI Food analysis")
                    .font(.title2)
                    .fontWeight(.bold)

                if let description = analysisResult.overallDescription {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Confidence level:")
                    ConfidenceBadge(level: analysisResult.confidence)
                    Spacer()
                    if let portions = analysisResult.totalFoodPortions {
                        Text("\(portions) Portions")
                            .font(.caption)
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("📊 Total nutritional values of the meal")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        let mealName = analysisResult.foodItemsDetailed.count == 1 ?
                            analysisResult.foodItemsDetailed.first?.name ?? "Meal" :
                            "Complete Meal"

                        let totalMeal = FoodItem(
                            name: mealName,
                            carbs: Decimal(analysisResult.totalCarbohydrates),
                            fat: Decimal(analysisResult.totalFat ?? 0),
                            protein: Decimal(analysisResult.totalProtein ?? 0),
                            source: "AI overall analysis • \(analysisResult.foodItemsDetailed.count) Food",
                            imageURL: nil
                        )
                        onCompleteMealSelected(totalMeal)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add all")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("\(analysisResult.foodItemsDetailed.count) Food")
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
                        label: "Carbs",
                        color: .orange
                    )

                    if let protein = analysisResult.totalProtein {
                        NutritionSummaryBadge(value: protein, unit: "g", label: "Protein", color: .green)
                    }

                    if let fat = analysisResult.totalFat {
                        NutritionSummaryBadge(value: fat, unit: "g", label: "Fat", color: .loopRed)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            Text("🍽️ Separate Foods")
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
                            source: "AI Analysis",
                            imageURL: nil
                        )
                        onFoodItemSelected(selectedFood)
                    }
                )
            }

            if let diabetesInfo = analysisResult.diabetesConsiderations {
                VStack(alignment: .leading, spacing: 8) {
                    Label("💉 Diabetes recommendations", systemImage: "cross.case.fill")
                        .font(.headline)
                    Text(diabetesInfo)
                        .font(.subheadline)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            if let notes = analysisResult.notes {
                VStack(alignment: .leading, spacing: 8) {
                    Label("📝 Notes", systemImage: "note.text")
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
