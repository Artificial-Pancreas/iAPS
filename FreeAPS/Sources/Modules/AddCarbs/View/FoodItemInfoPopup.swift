import Foundation
import SwiftUI

struct FoodItemInfoPopup: View {
    let foodItem: FoodItemDetailed
    let portionSize: Decimal

    // Helper to extract nutrition values
    private var nutritionValues: NutritionValues? {
        switch foodItem.nutrition {
        case let .per100(values):
            return values
        case let .perServing(values):
            return values
        }
    }

    private var isPerServing: Bool {
        if case .perServing = foodItem.nutrition {
            return true
        }
        return false
    }

    // Helper functions to avoid type inference issues
    private func shouldShowStandardServing(_ item: FoodItemDetailed) -> Bool {
        let hasDescription = item.standardServing != nil && !(item.standardServing?.isEmpty ?? true)
        let hasSize = item.standardServingSize != nil
        return hasDescription || hasSize
    }

    @ViewBuilder private func standardServingContent(
        foodItem: FoodItemDetailed,
        portionSize _: Decimal,
        unit _: String
    ) -> some View {
        if let servingDescription = foodItem.standardServing, !servingDescription.isEmpty {
            Text(servingDescription)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }

    private func standardServingTitle(foodItem: FoodItemDetailed, unit: String) -> String {
        if let servingSize = foodItem.standardServingSize {
            let formattedSize = String(format: "%.0f", Double(truncating: servingSize as NSNumber))
            return "Standard Serving - \(formattedSize) \(unit)"
        }
        return "Standard Serving"
    }

    var body: some View {
        let amount = String(format: "%.0f", Double(truncating: portionSize as NSNumber))
        let unit = NSLocalizedString((foodItem.units ?? .grams).localizedAbbreviation, comment: "")

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
                    InfoCard(icon: "eye.fill", title: "Visual Cues", content: visualCues, color: .blue, embedIcon: true)
                        .padding(.horizontal)
                }

                // Portion badge with source icon and confidence on same row
                HStack(spacing: 8) {
                    // Portion badge (neutral style matching food row)
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .opacity(0.3)

                        HStack(spacing: 3) {
                            switch foodItem.nutrition {
                            case .per100:
                                Text("\(amount)")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(unit)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.primary)
                                    .opacity(0.4)
                            case .perServing:
                                Text("\(amount)")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundColor(.primary)
                                Text(portionSize == 1 ? "serving" : "servings")
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

                    // Source icon and confidence on the right
                    HStack(spacing: 8) {
                        // Confidence badge (if AI source)
                        if foodItem.source.isAI, let confidence = foodItem.confidence {
                            ConfidenceBadge(level: confidence)
                        }

                        // Source icon
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

                        Text(isPerServing ? "Per serving" : "Per 100\(unit)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Divider()

                    DetailedNutritionRow(
                        label: "Carbs",
                        portionValue: foodItem.carbsInThisPortion,
                        per100Value: nutritionValues?.carbs,
                        unit: "g"
                    )
                    Divider()
                    DetailedNutritionRow(
                        label: "Protein",
                        portionValue: foodItem.proteinInThisPortion,
                        per100Value: nutritionValues?.protein,
                        unit: "g"
                    )
                    Divider()
                    DetailedNutritionRow(
                        label: "Fat",
                        portionValue: foodItem.fatInThisPortion,
                        per100Value: nutritionValues?.fat,
                        unit: "g"
                    )

                    // Optional additional nutrition
                    if let fiber = nutritionValues?.fiber, fiber > 0 {
                        Divider()
                        DetailedNutritionRow(
                            label: "Fiber",
                            portionValue: isPerServing ?
                                (foodItem.servingsMultiplier.map { fiber * $0 }) :
                                (foodItem.portionSize.map { fiber / 100 * $0 }),
                            per100Value: fiber,
                            unit: "g"
                        )
                    }
                    if let sugars = nutritionValues?.sugars, sugars > 0 {
                        Divider()
                        DetailedNutritionRow(
                            label: "Sugar",
                            portionValue: isPerServing ?
                                (foodItem.servingsMultiplier.map { sugars * $0 }) :
                                (foodItem.portionSize.map { sugars / 100 * $0 }),
                            per100Value: sugars,
                            unit: "g"
                        )
                    }
                    Divider()
                    DetailedNutritionRow(
                        label: "Calories",
                        portionValue: foodItem.caloriesInThisPortion,
                        per100Value: nutritionValues?.calories,
                        unit: "kcal"
                    )
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .padding(.horizontal)

                // Standard serving information
                if shouldShowStandardServing(foodItem) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(standardServingTitle(foodItem: foodItem, unit: unit), systemImage: "chart.bar.doc.horizontal")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        standardServingContent(foodItem: foodItem, portionSize: portionSize, unit: unit)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                // Metadata sections (preparation, visual cues, notes)
                VStack(alignment: .leading, spacing: 12) {
                    if let preparation = foodItem.preparationMethod, !preparation.isEmpty {
                        InfoCard(icon: "flame.fill", title: "Preparation", content: preparation, color: .orange, embedIcon: true)
                    }
                    if let notes = foodItem.assessmentNotes, !notes.isEmpty {
                        InfoCard(icon: "note.text", title: "Notes", content: notes, color: .gray, embedIcon: true)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}

private struct NutritionRow: View {
    let label: String
    let value: Decimal?
    let unit: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
            Spacer()
            if let value = value, value > 0 {
                HStack(spacing: 2) {
                    Text("\(Double(value), specifier: "%.1f")")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text(unit)
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
}

private struct DetailedNutritionRow: View {
    let label: String
    let portionValue: Decimal?
    let per100Value: Decimal?
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
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
                    Text(unit)
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
                    Text(unit)
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

struct SectionInfoPopup: View {
    let foodItemGroup: FoodItemGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                if let title = foodItemGroup.briefDescription, !title.isEmpty {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                }

                // Description
                if let description = foodItemGroup.overallDescription, !description.isEmpty {
                    InfoCard(icon: "text.quote", title: "Description", content: description, color: .gray, embedIcon: true)
                        .padding(.horizontal)
                }

                // Diabetes Recommendations
                if let diabetesInfo = foodItemGroup.diabetesConsiderations, !diabetesInfo.isEmpty {
                    InfoCard(
                        icon: "cross.case.fill",
                        title: "Diabetes Recommendations",
                        content: diabetesInfo,
                        color: .blue,
                        embedIcon: true
                    )
                    .padding(.horizontal)
                }

                Spacer(minLength: 8)
            }
            .padding(.vertical)
        }
    }
}

private struct InfoCard: View {
    let icon: String
    let title: String
    let content: String
    let color: Color
    let embedIcon: Bool

    init(icon: String, title: String, content: String, color: Color, embedIcon: Bool = false) {
        self.icon = icon
        self.title = title
        self.content = content
        self.color = color
        self.embedIcon = embedIcon
    }

    var body: some View {
        if embedIcon {
            HStack(alignment: .center, spacing: 0) {
                // Icon section with darker background
                ZStack(alignment: .center) {
                    color.opacity(0.25)
                        .cornerRadius(12, corners: [.topLeft, .bottomLeft])

                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                }
                .frame(width: 40)

                // Content section
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(color.opacity(0.08))
            .cornerRadius(12)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(color.opacity(0.08))
            .cornerRadius(12)
        }
    }
}
