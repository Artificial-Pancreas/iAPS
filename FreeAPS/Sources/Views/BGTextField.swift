import SwiftUI

struct BGTextField: View {
    let placeholder: String
    @Binding var mgdlValue: Decimal
    @Binding var units: GlucoseUnits
    var isDisabled: Bool
    var liveEditing: Bool // when true: update the value as the user types; when false: only update the value when the user finishes typing (closes the keyboard)

    init(
        _ placeholder: String,
        mgdlValue: Binding<Decimal>,
        units: Binding<GlucoseUnits>,
        isDisabled: Bool,
        liveEditing: Bool = false
    ) {
        self.placeholder = placeholder
        _mgdlValue = mgdlValue
        _units = units
        self.isDisabled = isDisabled
        self.liveEditing = liveEditing
    }

    private var mmolLFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
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
                DecimalTextField(placeholder, value: displayValue, formatter: mmolLFormatter, liveEditing: liveEditing)
                    .disabled(isDisabled)
            } else {
                DecimalTextField(placeholder, value: displayValue, formatter: mgdLFormatter, liveEditing: liveEditing)
                    .disabled(isDisabled)
            }

            Text(units == .mmolL ? LocalizedStringKey("mmol/L") : LocalizedStringKey("mg/dL"))
                .foregroundStyle(.secondary)
        }
    }
}
