import Foundation
import SwiftUI

struct FoodItemInfoPopup: View {
    let foodItem: FoodItemDetailed

    private var shouldShowStandardServing: Bool {
        let hasDescription = foodItem.standardServing != nil && !(foodItem.standardServing?.isEmpty ?? true)
        let hasSize = foodItem.standardServingSize != nil
        return hasDescription || hasSize
    }

    @ViewBuilder private func standardServingContent(foodItem: FoodItemDetailed) -> some View {
        if let servingDescription = foodItem.standardServing, !servingDescription.isEmpty {
            Text(servingDescription)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private func standardServingTitle(unit: String) -> String {
        if let servingSize = foodItem.standardServingSize {
            let formattedSize = String(format: "%.0f", Double(truncating: servingSize as NSNumber))
            return NSLocalizedString("Standard Serving", comment: "") + " - \(formattedSize) \(unit)"
        }
        return "Standard Serving"
    }

    var body: some View {
        let unit = (foodItem.units ?? .grams).dimension.symbol

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title and image
                HStack(alignment: .top, spacing: 12) {
                    Text(foodItem.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Product image (if available)
                    FoodItemLargeImage(imageURL: foodItem.imageURL)
                }
                .padding(.horizontal)

                if let visualCues = foodItem.visualCues, !visualCues.isEmpty {
                    FoodInfoCard(icon: "eye.fill", title: "Visual Cues", content: visualCues, color: .blue, embedIcon: true)
                        .padding(.horizontal)
                }

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .opacity(0.3)

                        HStack(spacing: 3) {
                            switch foodItem.nutrition {
                            case let .per100(_, portionSize):
                                Text(String(format: "%.0f", Double(truncating: portionSize as NSNumber)))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(unit)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .opacity(0.4)
                            case let .perServing(_, multiplier):
                                Text(String(format: "%.0f", Double(truncating: multiplier as NSNumber)))
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(multiplier == 1 ? "serving" : "servings")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .opacity(0.4)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray4))
                    .cornerRadius(10)

                    Spacer()

                    HStack(spacing: 8) {
                        if foodItem.source.isAI, let confidence = foodItem.confidence {
                            ConfidenceBadge(level: confidence)
                        }

                        Image(systemName: foodItem.source.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 8) {
                    // Header row
                    HStack(spacing: 8) {
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("This portion")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)

                        Text(foodItem.isPerServing ? "Per serving" : "Per 100\(unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    ForEach(NutrientType.allCases) { nutrient in
                        let nutrientValue = foodItem.nutrition.values[nutrient]
                        if nutrient.isPrimary || (nutrientValue != nil && nutrientValue! > 0) {
                            Divider()
                            DetailedNutritionRow(
                                localizedLabel: nutrient.localizedLabel,
                                portionValue: foodItem.nutrientInThisPortion(nutrient),
                                per100Value: nutrientValue,
                                unit: nutrient.unit
                            )
                        }
                    }

                    Divider()
                    DetailedNutritionRow(
                        localizedLabel: NSLocalizedString("Calories", comment: ""),
                        portionValue: foodItem.caloriesInThisPortion,
                        per100Value: foodItem.nutrition.values.calories,
                        unit: UnitEnergy.kilocalories
                    )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal)

                if shouldShowStandardServing {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(standardServingTitle(unit: unit), systemImage: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        standardServingContent(foodItem: foodItem)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if let preparation = foodItem.preparationMethod, !preparation.isEmpty {
                        FoodInfoCard(
                            icon: "flame.fill",
                            title: "Preparation",
                            content: preparation,
                            color: .orange,
                            embedIcon: true
                        )
                    }
                    if let notes = foodItem.assessmentNotes, !notes.isEmpty {
                        FoodInfoCard(icon: "note.text", title: "Notes", content: notes, color: .gray, embedIcon: true)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}

private struct DetailedNutritionRow: View {
    let localizedLabel: String
    let portionValue: Decimal?
    let per100Value: Decimal?
    let unit: Dimension

    var body: some View {
        HStack(spacing: 8) {
            Text(localizedLabel)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Per portion value
            if let value = portionValue, value > 0 {
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(unit.symbol)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 24, alignment: .leading)
                }
                .frame(width: 90, alignment: .trailing)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 90, alignment: .trailing)
            }

            // Per 100g/ml value
            if let value = per100Value, value > 0 {
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(unit.symbol)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 24, alignment: .leading)
                }
                .frame(width: 90, alignment: .trailing)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
