import SwiftUI

struct BGTextField: View {
    let placeholder: String
    @Binding var mgdlValue: Decimal
    @Binding var units: GlucoseUnits

    var isDisabled: Bool

    init(_ placeholder: String, mgdlValue: Binding<Decimal>, units: Binding<GlucoseUnits>, isDisabled: Bool) {
        self.placeholder = placeholder
        _mgdlValue = mgdlValue
        _units = units
        self.isDisabled = isDisabled
    }

    private var displayValue: Binding<Decimal> {
        Binding(
            get: { units == .mmolL ? mgdlValue.asMmolL : mgdlValue },
            set: { newValue in mgdlValue = units == .mmolL ? newValue.asMgdL.rounded : newValue.rounded }
        )
    }

    private var formatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }

    var body: some View {
        HStack {
            DecimalTextField(placeholder, value: displayValue, formatter: formatter)
                .disabled(isDisabled)
            Text(units == .mmolL ? "mmol/L" : "mg/dL")
                .foregroundStyle(.secondary)
        }
    }
}
