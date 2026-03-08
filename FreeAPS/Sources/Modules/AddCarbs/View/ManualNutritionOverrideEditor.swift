import Foundation
import SwiftUI

struct ManualNutritionOverrideEditor: View {
    @ObservedObject var state: FoodSearchStateModel
    @Environment(\.dismiss) private var dismiss

    @State private var editedValues: [NutrientType: String] = [:]

    @FocusState private var focusedField: NutrientType?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 0) {
                            ForEach(Array(NutrientType.allCases.enumerated()), id: \.element) { index, nutrient in
                                if index > 0 { Divider() }
                                NutritionOverrideRow(
                                    localizedLabel: nutrient.localizedLabel,
                                    text: Binding(
                                        get: { editedValues[nutrient] ?? "" },
                                        set: { editedValues[nutrient] = $0 }
                                    ),
                                    unit: nutrient.unit,
                                    placeholder: formatDecimal(state.searchResultsState.baseTotal(nutrient)),
                                    focusedField: $focusedField,
                                    fieldTag: nutrient
                                )
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
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button {
                            focusedField = nil
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
        .onAppear {
            initializeValues()
        }
        .onDisappear {
            focusedField = nil
        }
    }

    private func initializeValues() {
        for nutrient in NutrientType.allCases {
            if let override = state.searchResultsState.nutritionOverrides[nutrient] {
                let total = state.searchResultsState.baseTotal(nutrient) + override
                editedValues[nutrient] = formatDecimal(total)
            }
        }
    }

    private static let decimalFormatter: NumberFormatter = {
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

    private func parseDecimal(_ text: String) -> Decimal? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        return Decimal(string: cleaned)
    }

    private func saveChanges() {
        for nutrient in NutrientType.allCases {
            let text = editedValues[nutrient] ?? ""
            if let newValue = parseDecimal(text) {
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
    @Binding var text: String
    let unit: Dimension
    let placeholder: String
    @FocusState.Binding var focusedField: NutrientType?
    let fieldTag: NutrientType

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

                if text.isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.5))
                        .padding(.trailing, 8)
                }

                TextField("", text: $text)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: fieldTag)
                    .padding(.horizontal, 8)
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
