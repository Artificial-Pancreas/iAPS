import SwiftUI

struct BGTextField: View {
    let placeholder: String
    @Binding var mgdlValue: Decimal
    @Binding var units: GlucoseUnits

    var isDisabled: Bool

    @State private var currentUnits: GlucoseUnits

    init(placeholder: String, mgdlValue: Binding<Decimal>, units: Binding<GlucoseUnits>, isDisabled: Bool) {
        _currentUnits = State(initialValue: units.wrappedValue)
        self.placeholder = placeholder
        _mgdlValue = mgdlValue
        _units = units
        self.isDisabled = isDisabled
    }

    private var displayValue: Binding<Decimal> {
        Binding(
            get: { currentUnits == .mmolL ? mgdlValue.asMmolL : mgdlValue },
            set: { newValue in mgdlValue = currentUnits == .mmolL ? newValue.asMgdL.rounded : newValue }
        )
    }

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if units == .mgdL {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 1
        }
        return formatter
    }

    var body: some View {
        HStack {
            DecimalTextField(placeholder, value: displayValue, formatter: formatter)
                .disabled(isDisabled)
            Text(units == .mmolL ? "mmol/L" : "mg/dL")
                .foregroundStyle(.secondary)
        }
        .onChange(of: units) { newUnits in
            currentUnits = newUnits
        }
    }
}
