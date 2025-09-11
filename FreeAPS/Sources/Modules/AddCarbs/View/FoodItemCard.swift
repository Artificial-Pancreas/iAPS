import SwiftUI

struct FoodItemCard: View {
    let foodItem: FoodItemAnalysis
    let onSelect: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Kopfbereich mit Tap-Gesture für Auswahl
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(foodItem.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    // Expand/Collapse Button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Auswahl-Button
                Button(action: onSelect) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("Hinzufügen")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                // Portionsinformationen (immer sichtbar)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portion: \(foodItem.portionEstimate)")
                        .font(.subheadline)

                    if let usdaSize = foodItem.usdaServingSize {
                        Text("USDA Standard: \(usdaSize)")
                            .font(.caption)
                    }

                    if foodItem.servingMultiplier != 1.0 {
                        Text("Multiplikator: \(foodItem.servingMultiplier, specifier: "%.1f")x")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)

                // Nährwert-Badges (immer sichtbar)
                HStack(spacing: 8) {
                    NutritionBadge(value: foodItem.carbohydrates, unit: "g", label: "KH", color: .blue)

                    if let protein = foodItem.protein, protein > 0 {
                        NutritionBadge(value: protein, unit: "g", label: "P", color: .green)
                    }

                    if let fat = foodItem.fat, fat > 0 {
                        NutritionBadge(value: fat, unit: "g", label: "F", color: .orange)
                    }
                }
            }

            // Erweiterter Bereich (expandable)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    // Detaillierte Nährwerte
                    if let calories = foodItem.calories, calories > 0 {
                        HStack {
                            NutritionBadge(value: calories, unit: "kcal", label: "Energie", color: .red)

                            if let fiber = foodItem.fiber, fiber > 0 {
                                NutritionBadge(value: fiber, unit: "g", label: "Faser", color: .purple)
                            }
                        }
                    }

                    // Zusätzliche Informationen
                    VStack(alignment: .leading, spacing: 4) {
                        if let preparation = foodItem.preparationMethod, !preparation.isEmpty {
                            HStack(alignment: .top) {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Zubereitung: \(preparation)")
                                    .font(.caption)
                            }
                        }

                        if let visualCues = foodItem.visualCues, !visualCues.isEmpty {
                            HStack(alignment: .top) {
                                Image(systemName: "eye.fill")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                                Text("Visuelle Hinweise: \(visualCues)")
                                    .font(.caption)
                            }
                        }

                        if let notes = foodItem.assessmentNotes, !notes.isEmpty {
                            HStack(alignment: .top) {
                                Image(systemName: "note.text")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                                Text("Bewertung: \(notes)")
                                    .font(.caption)
                            }
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
    }
}
