import SwiftUI

struct BGTextField: View {
    let placeholder: String
    @Binding var mgdlValue: Decimal
    @Binding var units: Int
    private var formatter: NumberFormatter
    var isDisabled: Bool

    init(
        _ placeholder: String,
        mgdlValue: Binding<Decimal>,
        units: Binding<Int>,
        formatter: NumberFormatter,
        isDisabled: Bool
    ) {
        self.placeholder = placeholder
        _mgdlValue = mgdlValue
        _units = units
        self.formatter = formatter
        self.isDisabled = isDisabled
    }

    private var displayValue: Binding<Decimal> {
        Binding(
            get: { units == 1 ? mgdlValue.asMmolL : mgdlValue },
            set: { newValue in mgdlValue = units == 1 ? newValue.asMgdL : newValue }
        )
    }

    var body: some View {
        HStack {
            DecimalTextField(placeholder, value: displayValue, formatter: formatter)
                .disabled(isDisabled)
            Text(units == 1 ? LocalizedStringKey("mmol/L") : LocalizedStringKey("mg/dL"))
                .foregroundStyle(.secondary)
        }
    }
}
