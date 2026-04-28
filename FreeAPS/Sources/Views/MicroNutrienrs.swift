import CoreData
import SwiftUI

final class PresetViewModel: ObservableObject {
    @Published var micronutrients: [MicronutrientValue] = []

    private let context: NSManagedObjectContext
    private let preset: Presets

    init(preset: Presets, context: NSManagedObjectContext) {
        self.preset = preset
        self.context = context

        fetchMicronutrients()
    }

    func fetchMicronutrients() {
        micronutrients = preset.micronutrientValuesTyped()
    }

    // MARK: - Save (from AI model or manual input)

    func saveMicronutrients(_ values: [MicronutrientValue]) {
        do {
            try preset.applyMicronutrients(from: values, context: context)
            try context.save()
            fetchMicronutrients()
        } catch {
            print("❌ Failed to save micronutrients:", error)
        }
    }

    // MARK: - Example: Add single nutrient

    func addVitaminC() {
        let value = MicronutrientValue(
            substance: .vitaminC,
            amount: 60,
            amountPer100: 60
        )

        saveMicronutrients([value])
    }
}

struct PresetDetailView: View {
    @StateObject private var viewModel: PresetViewModel

    init(preset: Presets, context: NSManagedObjectContext) {
        _viewModel = StateObject(
            wrappedValue: PresetViewModel(preset: preset, context: context)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            let vitamins = viewModel.micronutrients.filter { $0.isVitamin }
            let minerals = viewModel.micronutrients.filter { !$0.isVitamin }

            List {
                Section("Micronutrients") {
                    ForEach(viewModel.micronutrients) { nutrient in
                        HStack {
                            Text(nutrient.name)

                            Spacer()

                            Text(nutrient.formattedAmount)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Button("Add Vitamin C") {
                viewModel.addVitaminC()
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Preset Nutrients")
    }
}

struct PresetNutrientRow: Identifiable {
    let id = UUID()
    let preset: Presets
    let nutrient: MicronutrientValue
}

struct AllNutrientsView: View {
    @FetchRequest(
        entity: Presets.entity(),
        sortDescriptors: []
    ) private var presets: FetchedResults<Presets>

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private func format(_ value: NSDecimalNumber?) -> String {
        Self.formatter.string(from: (value ?? 0) as NSNumber) ?? ""
    }

    var body: some View {
        List {
            ForEach(presets, id: \.dish) { preset in
                Section(preset.dish ?? "Unnamed") {
                    let micros = preset.micronutrientValuesTyped()

                    ForEach(micros) { nutrient in
                        HStack {
                            Text(nutrient.name)

                            Spacer()

                            Text(nutrient.formattedAmount)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func flattenPresets(_ presets: FetchedResults<Presets>) -> [PresetNutrientRow] {
        presets.flatMap { preset in
            let micros = preset.micronutrientValuesTyped()

            return micros.map {
                PresetNutrientRow(
                    preset: preset,
                    nutrient: $0
                )
            }
        }
    }
}

struct NutritionListView: View {
    let nutrition: AggregatedNutrition

    var body: some View {
        List {
            // MARK: Macros

            Section(header: Text("Macronutrients")) {
                ForEach(nutrition.macroDisplay) { nutrient in
                    NutrientRow(nutrient: nutrient)
                }
            }

            // MARK: Micros

            if !nutrition.microDisplay.isEmpty {
                Section(header: Text("Micronutrients")) {
                    ForEach(nutrition.microDisplay) { nutrient in
                        NutrientRow(nutrient: nutrient)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

struct NutrientRow: View {
    let nutrient: DisplayNutrient

    var body: some View {
        HStack {
            Text(nutrient.name)

            Spacer()

            Text(formattedValue)
                .fontWeight(nutrient.isPrimary ? .semibold : .regular)
        }
    }

    private var formattedValue: String {
        "\(NSDecimalNumber(decimal: nutrient.value).doubleValue, default: "%.1f") \(nutrient.unit)"
    }
}
