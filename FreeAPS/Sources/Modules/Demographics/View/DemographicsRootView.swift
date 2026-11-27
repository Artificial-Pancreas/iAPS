import SwiftUI
import Swinject

extension Demographics {
    struct RootView: BaseView {
        let resolver: Resolver
        /// pushed from Settings › Sharing: its Sharing row goes back there instead of pushing it again
        let fromSharing: Bool
        @StateObject var state: StateModel

        @Environment(\.dismiss) private var dismiss
        @State private var showSexInfo = false
        @State private var isBirthPickerShown = false
        // Local editing state for the feet/inches height entry (canonical store is cm). Filled from the height when
        // shown; only an edit of a field writes the height (`feetBinding`, `inchesBinding`).
        @State private var feet: Int = 0
        @State private var inches: Int = 0
        @FocusState private var focus: Field?

        /// the number fields, for the keyboard's Done
        private enum Field: Hashable {
            case weight
            case heightCm
            case feet
            case inches
        }

        init(resolver: Resolver, fromSharing: Bool = false) {
            self.resolver = resolver
            self.fromSharing = fromSharing
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        var body: some View {
            Form {
                Section {
                    HStack {
                        Picker("Sex", selection: $state.sex) {
                            ForEach(Sex.allCases) { sex in
                                Text(sex.displayName).tag(sex)
                            }
                        }
                        .pickerStyle(.menu)
                        Button {
                            showSexInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                    }

                    BirthDateField(birthDate: $state.pickedBirthDate, isPickerShown: $isBirthPickerShown)
                } footer: {
                    if state.demographics.setsReferenceIntakes {
                        Text("Used for reference intakes in Statistics › Nutrients.")
                    } else {
                        Text("Reference intakes in Statistics › Nutrients need Woman or Man and your birth date.")
                    }
                }

                Section {
                    weightRow
                    heightRow
                } header: {
                    Text("Body")
                }

                Section {
                    sharingRow
                } footer: {
                    Text(
                        "Stored on this phone. Settings › Sharing sets whether the daily statistics include your sex and age; with Online Backup on, the settings backup includes all of these."
                    )
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .scrollDismissesKeyboard(.interactively)
            // Once, on the Form (not per field): the number pads have no return key.
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .onAppear {
                if state.heightInFtIn { seedFeetInches() }
            }
            .alert("Why we ask about sex", isPresented: $showSexInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(
                    "Insulin sensitivity is shaped by sex hormones — estrogen and progesterone versus testosterone — not by gender identity. Choose the hormonal pattern your body currently runs on. For most people that is simply their sex; if you are on hormone therapy, choose the sex whose hormones you take.\n\nThis helps your own analysis and stays anonymous."
                )
            }
            .navigationBarTitle("About You")
        }

        // MARK: - Sharing

        /// To Settings › Sharing, or back to it when pushed from there (no Sharing › Demographics › Sharing › … chain).
        @ViewBuilder private var sharingRow: some View {
            let label = HStack {
                Text("Sharing")
                Spacer()
                Text(state.demographics.summary(uploading: state.uploadStats))
                    .foregroundStyle(.secondary)
            }
            if fromSharing {
                Button { dismiss() } label: { label.foregroundStyle(Color.primary) }
            } else {
                label.navigationLink(to: .sharing(fromDemographics: true), from: self)
            }
        }

        // MARK: - Body (canonical: weight kg, height cm)

        private var weightField: Binding<Double> {
            Binding(
                get: { Demographics.weightField(kg: state.weight, inLb: state.weightInLb) },
                set: { state.weight = Demographics.kg(field: $0, inLb: state.weightInLb) }
            )
        }

        private var heightCmField: Binding<Double> {
            Binding(
                get: { NSDecimalNumber(decimal: state.height).doubleValue },
                set: { state.height = Decimal(max(0, $0)) }
            )
        }

        /// Fills the fields from the height; writes nothing.
        private func seedFeetInches() {
            let split = Demographics.feetInches(cm: NSDecimalNumber(decimal: state.height).doubleValue)
            feet = split.feet
            inches = split.inches
        }

        private var feetBinding: Binding<Int> {
            Binding(
                get: { feet },
                set: { newValue in
                    feet = newValue
                    commitFeetInches()
                }
            )
        }

        private var inchesBinding: Binding<Int> {
            Binding(
                get: { inches },
                set: { newValue in
                    inches = newValue
                    commitFeetInches()
                }
            )
        }

        private func commitFeetInches() {
            state.height = Demographics.height(feet: feet, inches: inches, keeping: state.height)
        }

        private var weightRow: some View {
            HStack {
                Text("Weight")
                Spacer()
                TextField("—", value: weightField, format: .number.precision(.fractionLength(0 ... 1)))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .weight)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 70)
                Picker("", selection: $state.weightInLb) {
                    Text("kg").tag(false)
                    Text("lb").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }

        private var heightRow: some View {
            HStack {
                Text("Height")
                Spacer()
                if state.heightInFtIn {
                    TextField("ft", value: feetBinding, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .feet)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 34)
                    Text("ft").foregroundStyle(.secondary)
                    TextField("in", value: inchesBinding, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .inches)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 34)
                    Text("in").foregroundStyle(.secondary)
                } else {
                    TextField("—", value: heightCmField, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .focused($focus, equals: .heightCm)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70)
                }
                Picker("", selection: $state.heightInFtIn) {
                    Text("cm").tag(false)
                    Text("ft/in").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .onChange(of: state.heightInFtIn) {
                    if state.heightInFtIn { seedFeetInches() }
                }
            }
        }
    }
}

// MARK: - The birth date

/// The birth date, a day or not set (nil): a "Born" row showing it (or "Not set") that opens a wheel below it, and
/// under the wheel "Clear birth date" back to not set. Opening the wheel doesn't set it (it starts on 1 January 30
/// years ago): turning it does, or, while not set, "Set to 1 Jan 1996" under it, the day it shows (someone born that
/// day needn't turn it away and back). The wheel shows and keeps the day in `DemographicsSharing.birthCalendar`'s
/// time zone, so the day picked is the day kept, wherever the phone is.
struct BirthDateField: View {
    @Binding var birthDate: Date?
    @Binding var isPickerShown: Bool

    private var range: ClosedRange<Date> { DemographicsSharing.birthDateRange() }

    /// where the wheel starts while not set
    private var startDay: Date { DemographicsSharing.birthWheelStart() }

    private var wheelSelection: Binding<Date> {
        Binding(
            get: { birthDate ?? startDay },
            set: { birthDate = DemographicsSharing.birthDate(day: $0) }
        )
    }

    var body: some View {
        HStack {
            Text("Born")
            Spacer()
            Button {
                withAnimation { isPickerShown.toggle() }
            } label: {
                Text(
                    birthDate.flatMap(Demographics.bornShortText) ??
                        NSLocalizedString("Not set", comment: "Demographics: the birth date not set")
                )
                .foregroundStyle(birthDate != nil ? Color.primary : Color.secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.borderless)
        }

        if isPickerShown {
            DatePicker("Born", selection: wheelSelection, in: range, displayedComponents: [.date])
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.timeZone, DemographicsSharing.birthCalendar.timeZone)
            if birthDate != nil {
                Button("Clear birth date", role: .destructive) {
                    birthDate = nil
                    withAnimation { isPickerShown = false }
                }
            } else if let shown = Demographics.bornShortText(startDay) {
                Button(String(
                    format: NSLocalizedString(
                        "Set to %@",
                        comment: "Demographics: the birth date set to the day the wheel shows, \"1 Jan 1996\""
                    ),
                    shown
                )) {
                    birthDate = DemographicsSharing.birthDate(day: startDay)
                }
            }
        }
    }
}

// MARK: - The Reference intakes sheet (Statistics › Nutrients)

/// Opened from the Nutrients screen without reference intakes: the sex and the birth date, saved to Settings ›
/// Demographics. Settings › Sharing's toggles are left as they are (but a value cleared turns its toggle off,
/// `DemographicsSharing.settingSex`, `settingBirthDate`: Save never clears one). Save needs Woman or Man and the
/// birth date (`DemographicsSharing.canSaveReferenceIntakes`).
struct ReferenceIntakesSheet: View {
    let settingsManager: SettingsManager

    @Environment(\.dismiss) private var dismiss
    @State private var sex: Sex
    @State private var birthDate: Date?
    @State private var isBirthPickerShown = true

    init(settingsManager: SettingsManager, settings: FreeAPSSettings) {
        self.settingsManager = settingsManager
        _sex = State(initialValue: Sex.savedSettings(settings.sexSetting))
        _birthDate = State(initialValue: settings.demographics.shownBirthDay)
    }

    private var canSave: Bool {
        DemographicsSharing.canSaveReferenceIntakes(sex: sex, birthDate: birthDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sex", selection: $sex) {
                        ForEach(Sex.allCases) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Sex")
                }

                Section {
                    BirthDateField(birthDate: $birthDate, isPickerShown: $isBirthPickerShown)
                } footer: {
                    Text(
                        "Reference intakes use Woman or Man. Saved in Settings › About You. The daily statistics include them only if you turn that on in Settings › Sharing; with Online Backup on, the settings backup includes them."
                    )
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationTitle("Reference intakes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.fraction(0.7), .large])
    }

    private func save() {
        guard let birthDate else { return }
        let sexSetting = sex.saveSetting()
        let day = DemographicsSharing.birthDate(day: birthDate)
        Task {
            await settingsManager.updateSettings { settings in
                var updated = settings
                updated.demographics = settings.demographics.settingSex(sexSetting).settingBirthDate(day)
                return updated
            }
        }
        dismiss()
    }
}
