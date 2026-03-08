import Foundation
import SwiftUI

struct FoodItemRow: View {
    let foodItem: FoodItemDetailed
    let portionSize: Decimal
    let onPortionChange: ((Decimal) -> Void)?
    let onDelete: (() -> Void)?
    let onPersist: ((FoodItemDetailed) -> Void)?
    let savedFoodIds: Set<UUID>
    let allExistingTags: Set<String>
    let isFirst: Bool
    let isLast: Bool

    @State private var showItemInfo = false
    @State private var showPortionAdjuster = false
    @State private var sliderMultiplier: Double = 1.0

    private var isSaved: Bool {
        savedFoodIds.contains(foodItem.id)
    }

    private var hasNutritionInfo: Bool {
        switch foodItem.nutrition {
        case let .per100(values): return !values.isEmpty
        case let .perServing(values): return !values.isEmpty
        }
    }

    private var isManualEntry: Bool {
        foodItem.source == .manual
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main Row Content
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(foodItem.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if foodItem.source.isAI, let confidence = foodItem.confidence {
                            ConfidenceBadge(level: confidence)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        Button(action: {
                            showPortionAdjuster = true
                        }) {
                            PortionSizeBadge(
                                value: portionSize,
                                color: .orange,
                                icon: "scalemass.fill",
                                foodItem: foodItem
                            )
                        }
                        .buttonStyle(.plain)

                        if case .per100 = foodItem.nutrition {
                            if let servingSize = foodItem.standardServingSize {
                                Text("\(Double(portionSize / servingSize), specifier: "%.1f")× serving")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .opacity(0.7)
                            }
                        }
                    }
                }

                if foodItem.imageURL != nil {
                    FoodItemThumbnail(imageURL: foodItem.imageURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                showItemInfo = true
            }
            .contextMenu {
                if onPortionChange != nil {
                    Button {
                        showPortionAdjuster = true
                    } label: {
                        Label("Edit Portion", systemImage: "slider.horizontal.3")
                    }
                }

                if foodItem.source != .database {
                    if isSaved {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.secondary)
                    } else if let onPersist = onPersist {
                        Button {
                            onPersist(foodItem)
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                }

                if let onDelete = onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove from meal", systemImage: "trash")
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(NutrientType.allCases.filter { $0.isPrimary }) { nutrient in
                    NutritionBadgePlain(
                        value: foodItem.nutrient(nutrient, forPortion: portionSize),
                        localizedLabel: nutrient.localizedLabel,
                        color: nutrient.badgeColor
                    )
                }
                NutritionBadgePlain(
                    value: foodItem.calories(forPortion: portionSize),
                    unit: UnitEnergy.kilocalories,
                    color: NutritionBadgeConfig.caloriesColor
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .padding(.top, isFirst ? 8 : 0)
        .padding(.bottom, isLast ? 8 : 0)
        .background(Color(.systemGray6))
        .when(onDelete != nil) { view in
            view.swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    onDelete?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
        .when(onPortionChange != nil) { view in
            view.swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    showPortionAdjuster = true
                } label: {
                    Label("Edit Portion", systemImage: "slider.horizontal.3")
                }
                .tint(.orange)
            }
        }
        .when(onPortionChange != nil) { view in
            view.sheet(isPresented: $showPortionAdjuster) {
                PortionAdjusterView(
                    currentPortion: portionSize,
                    foodItem: foodItem,
                    sliderMultiplier: $sliderMultiplier,
                    onSave: { newPortion in
                        onPortionChange?(newPortion)
                        showPortionAdjuster = false
                    },
                    onReset: {
                        switch foodItem.nutrition {
                        case .per100:
                            return foodItem.portionSize != nil
                        case .perServing:
                            return foodItem.servingsMultiplier != nil
                        }
                    }() ? {
                        switch foodItem.nutrition {
                        case .per100:
                            if let original = foodItem.portionSize {
                                onPortionChange?(original)
                                showPortionAdjuster = false
                            }
                        case .perServing:
                            if let original = foodItem.servingsMultiplier {
                                onPortionChange?(original)
                                showPortionAdjuster = false
                            }
                        }
                    } : nil,
                    onCancel: {
                        showPortionAdjuster = false
                    }
                )
                .presentationDetents([.height({
                    let hasReset: Bool
                    switch foodItem.nutrition {
                    case .per100:
                        hasReset = foodItem.portionSize != nil
                    case .perServing:
                        hasReset = foodItem.servingsMultiplier != nil
                    }
                    return hasNutritionInfo ? (hasReset ? 420 : 400) : (hasReset ? 340 : 300)
                }())])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showItemInfo) {
            FoodItemInfoPopup(foodItem: foodItem, portionSize: portionSize)
                .presentationDetents([.height(preferredItemInfoHeight(for: foodItem)), .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: portionSize) { _, newValue in
            sliderMultiplier = Double(newValue)
        }
        .onAppear {
            sliderMultiplier = Double(portionSize)
        }
    }

    private func preferredItemInfoHeight(for item: FoodItemDetailed) -> CGFloat {
        var base: CGFloat = 480
        if let notes = item.assessmentNotes, !notes.isEmpty { base += 40 }
        if let prep = item.preparationMethod, !prep.isEmpty { base += 30 }
        if let cues = item.visualCues, !cues.isEmpty { base += 30 }
        if (item.standardServing != nil && !item.standardServing!.isEmpty) ||
            item.standardServingSize != nil { base += 40 }
        return min(max(base, 460), 680)
    }
}

extension FoodItemRow {
    private struct PortionSizeBadge: View {
        let value: Decimal
        let color: Color
        let icon: String
        let foodItem: FoodItemDetailed

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .opacity(0.3)
                }
                HStack(spacing: 2) {
                    switch foodItem.nutrition {
                    case .per100:
                        Text("\(Double(value), specifier: "%.0f")")
                            .font(.system(size: 15, weight: .bold))
                        Text((foodItem.units ?? .grams).dimension.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.4)
                    case .perServing:
                        Text("\(Double(value), specifier: "%.1f")")
                            .font(.system(size: 15, weight: .bold))
                        Text(value == 1 ? "serving" : "servings")
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.4)
                    }
                }
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(.systemGray4))
            .cornerRadius(8)
        }
    }

    private struct PortionAdjusterView: View {
        let currentPortion: Decimal
        let foodItem: FoodItemDetailed
        @Binding var sliderMultiplier: Double
        let onSave: (Decimal) -> Void
        let onReset: (() -> Void)?
        let onCancel: () -> Void

        private var isPerServing: Bool {
            if case .perServing = foodItem.nutrition {
                return true
            }
            return false
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

        private let formatter: NumberFormatter = {
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

        private var sliderRange: ClosedRange<Double> {
            switch foodItem.nutrition {
            case .per100:
                10.0 ... 600.0
            case .perServing:
                0.25 ... 10.0
            }
        }

        private var sliderStep: Double.Stride {
            switch foodItem.nutrition {
            case .per100:
                5.0
            case .perServing:
                0.25
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
                return "600\(unit)"
            case .perServing:
                return "10x"
            }
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
                            (formatter.string(from: calculatedPortion as NSNumber) ?? "") +
                                NSLocalizedString(unit, comment: "")
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
                    Slider(value: $sliderMultiplier, in: sliderRange, step: sliderStep)
                        .tint(.orange)

                    HStack {
                        Text(NSLocalizedString(sliderMinLabel, comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(NSLocalizedString(sliderMaxLabel, comment: ""))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Display nutritional information if available
                    if hasNutritionInfo {
                        HStack(spacing: 8) {
                            ForEach(NutrientType.allCases.filter { $0.isPrimary }) { nutrient in
                                let value = foodItem.nutrient(nutrient, forPortion: calculatedPortion)
                                if value > 0 {
                                    NutritionBadge(
                                        value: value,
                                        localizedLabel: nutrient.localizedLabel,
                                        color: nutrient.badgeColor
                                    )
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            let calories = foodItem.calories(forPortion: calculatedPortion)
                            if calories > 0 {
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
                                        (formatter.string(from: original as NSNumber) ?? "") +
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
                        let servingString = original == 1 ? " serving" : " servings"
                        Button(action: resetSliderToOriginal) {
                            HStack {
                                Text(
                                    NSLocalizedString("Reset to ", comment: "") +
                                        (formatter.string(from: original as NSNumber) ?? "") +
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

        private var hasNutritionInfo: Bool {
            switch foodItem.nutrition {
            case let .per100(values): return !values.isEmpty
            case let .perServing(values): return !values.isEmpty
            }
        }
    }
}
