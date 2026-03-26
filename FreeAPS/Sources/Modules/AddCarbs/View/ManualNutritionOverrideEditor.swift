import Foundation
import SwiftUI

struct ManualNutritionOverrideEditor: View {
    @ObservedObject var state: FoodSearchStateModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedValues: [NutrientType: Decimal] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 0) {
                            ForEach(Array(NutrientType.allCases.enumerated()), id: \.element) { index, nutrient in
                                if nutrient.isMacro {
                                    if index > 0 { Divider() }
                                    NutritionOverrideRow(
                                        localizedLabel: nutrient.localizedLabel,
                                        value: Binding(
                                            get: { editedValues[nutrient] },
                                            set: { updated in
                                                if let updated {
                                                    editedValues[nutrient] = updated
                                                } else {
                                                    editedValues.removeValue(forKey: nutrient)
                                                }
                                            }
                                        ),
                                        unit: nutrient.unit,
                                        placeholder: formatDecimal(state.searchResultsState.baseTotal(nutrient))
                                    )
                                }
                            }
                        }
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)

                        Button(role: .destructive) {
                            state.searchResultsState.nutritionOverrides.removeAll()
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }

                // Action buttons at bottom
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(10)

                    Button("Save") {
                        saveChanges()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
            }
            .navigationTitle("Edit Totals")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            initializeValues()
        }
    }

    private func initializeValues() {
        for nutrient in NutrientType.allCases {
            if let override = state.searchResultsState.nutritionOverrides[nutrient] {
                let total = state.searchResultsState.baseTotal(nutrient) + override
                editedValues[nutrient] = total
            }
        }
    }

    fileprivate static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    private func formatDecimal(_ value: Decimal) -> String {
        Self.decimalFormatter.string(from: NSDecimalNumber(decimal: value)) ?? "0"
    }

    private func saveChanges() {
        for nutrient in NutrientType.allCases {
            if let newValue = editedValues[nutrient] {
                state.searchResultsState.nutritionOverrides[nutrient] =
                    newValue - state.searchResultsState.baseTotal(nutrient)
            } else {
                state.searchResultsState.nutritionOverrides.removeValue(forKey: nutrient)
            }
        }
        dismiss()
    }
}

private struct NutritionOverrideRow: View {
    let localizedLabel: String
    @Binding var value: Decimal?
    let unit: Dimension
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Text(localizedLabel)
                .font(.subheadline)
                .foregroundColor(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )

                if value == nil {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.trailing, 8)
                }

                OptionalDecimalTextField(
                    "",
                    value: $value,
                    formatter: ManualNutritionOverrideEditor.decimalFormatter,
                    liveEditing: true
                )
                .foregroundColor(.primary)
                .padding(.horizontal, 8)
                .cornerRadius(4)
                .background(Color.clear)
            }
            .frame(width: 100, height: 32)

            Text(unit.symbol)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 28, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
