import Foundation
import SwiftUI

struct FoodItemRow: View {
    let foodItem: FoodItemDetailed
    let onPortionChange: ((Decimal) -> Void)?
    let onDelete: (() -> Void)?
    let onPersist: ((FoodItemDetailed) -> Void)?
    let savedFoodIds: Set<UUID>
    let allExistingTags: Set<String>
    let isFirst: Bool
    let isLast: Bool

    @State private var showItemInfo = false
    @State private var showPortionAdjuster = false

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
                                value: foodItem.portionSizeOrMultiplier,
                                color: .orange,
                                icon: "scalemass.fill",
                                foodItem: foodItem
                            )
                        }
                        .buttonStyle(.plain)

                        if case .per100 = foodItem.nutrition {
                            if let servingSize = foodItem.standardServingSize {
                                Text("\(Double(foodItem.portionSizeOrMultiplier / servingSize), specifier: "%.1f")× serving")
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
                        value: foodItem.nutrientInThisPortion(nutrient) ?? 0,
                        localizedLabel: nutrient.localizedLabel,
                        color: nutrient.badgeColor
                    )
                }
                NutritionBadgePlain(
                    value: foodItem.caloriesInThisPortion,
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
                    foodItem: foodItem,
                    onSave: { newPortion in
                        onPortionChange?(newPortion)
                        showPortionAdjuster = false
                    },
                    onCancel: {
                        showPortionAdjuster = false
                    }
                )
                .presentationDetents([
                    .height(foodItem.hasNutritionValues ? 420 : 340)
                ])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showItemInfo) {
            FoodItemInfoPopup(foodItem: foodItem)
                .presentationDetents([.height(foodItem.preferredInfoSheetHeight()), .large])
                .presentationDragIndicator(.visible)
        }
    }
}
