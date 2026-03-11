import Foundation
import SwiftUI

struct PortionAdjusterView: View {
    let currentPortion: Decimal
    let foodItem: FoodItemDetailed
    @Binding var sliderMultiplier: Double
    let onSave: (Decimal) -> Void
    let onReset: (() -> Void)?
    let onCancel: () -> Void

    @State private var sliderUpperBound: Double

    init(
        currentPortion: Decimal,
        foodItem: FoodItemDetailed,
        sliderMultiplier: Binding<Double>,
        onSave: @escaping (Decimal) -> Void,
        onReset: (() -> Void)?,
        onCancel: @escaping () -> Void
    ) {
        self.currentPortion = currentPortion
        self.foodItem = foodItem
        _sliderMultiplier = sliderMultiplier
        self.onSave = onSave
        self.onReset = onReset
        self.onCancel = onCancel
        let initialMax: Double = switch foodItem.nutrition {
        case .per100: 600.0
        case .perServing: 10.0
        }
        _sliderUpperBound = State(initialValue: initialMax)
    }

    private var unit: String {
        switch foodItem.nutrition {
        case .per100:
            return (foodItem.units?.dimension ?? UnitMass.grams).symbol
        case .perServing:
            return NSLocalizedString("serving", comment: "")
        }
    }

    var calculatedPortion: Decimal {
        Decimal(sliderMultiplier)
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private func resetSliderToOriginal() {
        switch foodItem.nutrition {
        case .per100:
            if let original = foodItem.portionSize {
                sliderMultiplier = Double(original)
            }
        case .perServing:
            if let original = foodItem.servingsMultiplier {
                sliderMultiplier = Double(original)
            }
        }
    }

    private func formattedServingMultiplier(_ value: Decimal) -> String {
        let doubleValue = Double(truncating: value as NSNumber)
        return String(format: "%.2f×", doubleValue)
    }

    private var sliderMin: Double {
        switch foodItem.nutrition {
        case .per100: 10.0
        case .perServing: 0.25
        }
    }

    private var sliderStep: Double {
        switch foodItem.nutrition {
        case .per100: 5.0
        case .perServing: 0.25
        }
    }

    private var sliderMinLabel: String {
        switch foodItem.nutrition {
        case .per100:
            return "10\(unit)"
        case .perServing:
            return "0.25x"
        }
    }

    private var sliderMaxLabel: String {
        switch foodItem.nutrition {
        case .per100:
            return "\(Int(sliderUpperBound))\(unit)"
        case .perServing:
            return String(format: "%.2g×", sliderUpperBound)
        }
    }

    private func stepDown() {
        sliderMultiplier = max(sliderMin, sliderMultiplier - sliderStep)
    }

    private func stepUp() {
        let newValue = sliderMultiplier + sliderStep
        if newValue > sliderUpperBound {
            sliderUpperBound = newValue
        }
        sliderMultiplier = newValue
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text(foodItem.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                FoodItemLargeImage(imageURL: foodItem.imageURL)
            }
            .padding(.horizontal)
            .padding(.top)

            VStack(spacing: 8) {
                switch foodItem.nutrition {
                case .per100:
                    Text(
                        (Self.formatter.string(from: calculatedPortion as NSNumber) ?? "") +
                            unit
                    )
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.orange)
                case .perServing:
                    Text(formattedServingMultiplier(calculatedPortion))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.orange)
                }
            }

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button(action: stepDown) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(sliderMultiplier <= sliderMin ? .secondary : .orange)
                    }
                    .disabled(sliderMultiplier <= sliderMin)

                    Slider(value: $sliderMultiplier, in: sliderMin ... sliderUpperBound, step: sliderStep)
                        .tint(.orange)

                    Button(action: stepUp) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                }

                HStack {
                    Text(sliderMinLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(sliderMaxLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if foodItem.hasNutritionValues {
                    HStack(spacing: 8) {
                        ForEach(NutrientType.allCases.filter { $0.isPrimary }) { nutrient in
                            if let value = foodItem.nutrientInPortionOrServings(
                                nutrient,
                                portionOrMultiplier: calculatedPortion
                            ), value > 0 {
                                NutritionBadge(
                                    value: value,
                                    localizedLabel: nutrient.localizedLabel,
                                    color: nutrient.badgeColor
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        if let calories = foodItem.caloriesInPortionOrServings(portionOrMultiplier: calculatedPortion),
                           calories > 0
                        {
                            NutritionBadge(
                                value: calories,
                                unit: UnitEnergy.kilocalories,
                                color: NutritionBadgeConfig.caloriesColor
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)

            // Show reset button if original portion size or servings multiplier is available
            switch foodItem.nutrition {
            case .per100:
                if let original = foodItem.portionSize {
                    Button(action: resetSliderToOriginal) {
                        HStack {
                            Text(
                                NSLocalizedString("Reset to ", comment: "") +
                                    (Self.formatter.string(from: original as NSNumber) ?? "") +
                                    unit
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            case .perServing:
                if let original = foodItem.servingsMultiplier {
                    let servingString = original == 1 ? "serving" : "servings"
                    Button(action: resetSliderToOriginal) {
                        HStack {
                            Text(
                                NSLocalizedString("Reset to ", comment: "") +
                                    (Self.formatter.string(from: original as NSNumber) ?? "") +
                                    " " +
                                    NSLocalizedString(servingString, comment: "")
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(10)

                Button("Apply") {
                    onSave(calculatedPortion)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}
