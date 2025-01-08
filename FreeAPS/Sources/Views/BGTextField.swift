import SwiftUI

struct BGTextField: View {
    let placeholder: String
    @Binding var mgdlValue: Decimal
    @Binding var units: GlucoseUnits
    var isDisabled: Bool

    init(
        _ placeholder: String,
        mgdlValue: Binding<Decimal>,
        units: Binding<GlucoseUnits>,
        isDisabled: Bool
    ) {
        self.placeholder = placeholder
        _mgdlValue = mgdlValue
        _units = units
        self.isDisabled = isDisabled
    }

    private var mmolLFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter
    }

    private var mgdLFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var displayValue: Binding<Decimal> {
        Binding(
            get: { units == .mmolL ? mgdlValue.asMmolL : mgdlValue },
            set: { newValue in mgdlValue = units == .mmolL ? newValue.asMgdL : newValue }
        )
    }

    var body: some View {
        HStack {
            if units == .mmolL {
                DecimalTextField(placeholder, value: displayValue, formatter: mmolLFormatter)
                    .disabled(isDisabled)
            } else {
                DecimalTextField(placeholder, value: displayValue, formatter: mgdLFormatter)
                    .disabled(isDisabled)
            }

            Text(units == .mmolL ? LocalizedStringKey("mmol/L") : LocalizedStringKey("mg/dL"))
                .foregroundStyle(.secondary)
        }
    }
}
