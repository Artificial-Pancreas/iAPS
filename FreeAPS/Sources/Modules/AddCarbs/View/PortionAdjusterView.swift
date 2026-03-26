import Foundation
import SwiftUI

struct PortionAdjusterView: View {
    let foodItem: FoodItemDetailed
    let onSave: (Decimal) -> Void
    let onCancel: () -> Void

    @State private var sliderValue: Double
    @State private var sliderUpperBound: Double

    init(
        foodItem: FoodItemDetailed,
        onSave: @escaping (Decimal) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.foodItem = foodItem
        self.onSave = onSave
        self.onCancel = onCancel
        let initialMax: Double = switch foodItem.nutrition {
        case .per100: 600.0
        case .perServing: 10.0
        }
        let initialSliderValue = NSDecimalNumber(decimal: foodItem.portionSizeOrMultiplier).doubleValue
        _sliderValue = State(initialValue: initialSliderValue)
        _sliderUpperBound = State(initialValue: Swift.max(initialMax, initialSliderValue))
    }

    private var unit: String {
        switch foodItem.nutrition {
        case .per100:
            return (foodItem.units?.dimension ?? UnitMass.grams).symbol
        case .perServing:
            return NSLocalizedString("serving", comment: "")
        }
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private func resetSliderToOriginal() {
        switch foodItem.nutrition {
        case let .per100(_, portionSize):
            sliderValue = Double(portionSize)
        case let .perServing(_, multiplier):
            sliderValue = Double(multiplier)
        }
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
        sliderValue = max(sliderMin, sliderValue - sliderStep)
    }

    private func stepUp() {
        let newValue = sliderValue + sliderStep
        if newValue > sliderUpperBound {
            sliderUpperBound = newValue
        }
        sliderValue = newValue
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
                        (Self.formatter.string(from: sliderValue as NSNumber) ?? "") +
                            unit
                    )
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.orange)
                case .perServing:
                    Text(String(format: "%.2f×", sliderValue))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.orange)
                }
            }

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button(action: stepDown) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(sliderValue <= sliderMin ? .secondary : .orange)
                    }
                    .disabled(sliderValue <= sliderMin)

                    Slider(value: $sliderValue, in: sliderMin ... sliderUpperBound, step: sliderStep)
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
                                portionOrMultiplier: Decimal(sliderValue)
                            ), value > 0 {
                                NutritionBadge(
                                    value: value,
                                    localizedLabel: nutrient.localizedLabel,
                                    color: nutrient.badgeColor
                                )
                                .frame(maxWidth: .infinity)
                            }
                        }
                        if let calories = foodItem.caloriesInPortionOrServings(portionOrMultiplier: Decimal(sliderValue)),
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
            case let .per100(_, portionSize):
                Button(action: resetSliderToOriginal) {
                    HStack {
                        Text(
                            NSLocalizedString("Reset to ", comment: "") +
                                (Self.formatter.string(from: portionSize as NSNumber) ?? "") +
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
            case let .perServing(_, multiplier):
                let servingString = multiplier == 1 ? "serving" : "servings"
                Button(action: resetSliderToOriginal) {
                    HStack {
                        Text(
                            NSLocalizedString("Reset to ", comment: "") +
                                (Self.formatter.string(from: multiplier as NSNumber) ?? "") +
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
                    onSave(Decimal(sliderValue))
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
