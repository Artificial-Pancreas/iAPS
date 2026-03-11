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
                        value: foodItem.nutrientInPortionOrServings(nutrient, portionOrMultiplier: portionSize) ?? 0,
                        localizedLabel: nutrient.localizedLabel,
                        color: nutrient.badgeColor
                    )
                }
                NutritionBadgePlain(
                    value: foodItem.caloriesInPortionOrServings(portionOrMultiplier: portionSize) ?? 0,
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
                    return foodItem.hasNutritionValues ? (hasReset ? 420 : 400) : (hasReset ? 340 : 300)
                }())])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showItemInfo) {
            FoodItemInfoPopup(foodItem: foodItem, portionSize: portionSize)
                .presentationDetents([.height(foodItem.preferredInfoSheetHeight()), .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: portionSize) { _, newValue in
            sliderMultiplier = Double(newValue)
        }
        .onAppear {
            sliderMultiplier = Double(portionSize)
        }
    }
}
