import SwiftUI
import Swinject

public enum Sex: String, CaseIterable, Identifiable {
    case woman = "Woman"
    case man = "Man"
    case other = "Other"
    case secret = "Prefer not to say"
    public var id: Self { self }

    /// Only Woman/Man carry a usable hormonal prior for the stats engine.
    var hasHormonalSignal: Bool {
        self == .woman || self == .man
    }
}

extension Sex {
    static func savedSettings(_ sexSetting: Int) -> Sex {
        switch sexSetting {
        case 0:
            return .woman
        case 1:
            return .man
        case 2:
            return .other
        default:
            return .secret
        }
    }

    func saveSetting() -> Int {
        switch self {
        case .woman: return 0
        case .man: return 1
        case .other: return 2
        case .secret: return 3
        }
    }
}

extension Sharing {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state: StateModel

        @State private var display: Bool = false
        @State private var copied: Bool = false
        @State private var showSexInfo: Bool = false
        @State private var logsRevoked: Bool = false
        // Local editing state for the feet/inches height entry (canonical store is cm).
        @State private var feet: Int = 0
        @State private var inches: Int = 0

        private let demographicsInfoURL = URL(string: "https://open-iaps.app/demographics")!

        let dateRange: ClosedRange<Date> = {
            let calendar = Calendar.current
            let year = Date.now.year
            let month = Date.now.month

            let startComponents = DateComponents(year: 1920, month: 1)
            let endComponents = DateComponents(year: year, month: month)
            return calendar.date(from: startComponents)!
                ...
                calendar.date(from: endComponents)!
        }()

        init(resolver: Resolver) {
            self.resolver = resolver
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        // MARK: - Unit conversion bindings (canonical: weight kg, height cm)

        private static let lbPerKg = 2.2046226218
        private static let cmPerInch = 2.54

        private var weightField: Binding<Double> {
            Binding(
                get: {
                    let kg = NSDecimalNumber(decimal: state.weight).doubleValue
                    return state.weightInLb ? kg * Self.lbPerKg : kg
                },
                set: { newValue in
                    let kg = state.weightInLb ? newValue / Self.lbPerKg : newValue
                    state.weight = Decimal(max(0, kg))
                }
            )
        }

        private var heightCmField: Binding<Double> {
            Binding(
                get: { NSDecimalNumber(decimal: state.height).doubleValue },
                set: { state.height = Decimal(max(0, $0)) }
            )
        }

        private func seedFeetInches() {
            let totalInches = NSDecimalNumber(decimal: state.height).doubleValue / Self.cmPerInch
            feet = Int(totalInches / 12)
            inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        }

        private func commitFeetInches() {
            let totalInches = Double(feet) * 12 + Double(inches)
            state.height = Decimal(totalInches * Self.cmPerInch)
        }

        /// Auto-revoke Daily Log upload the moment the demographics stop qualifying,
        /// and tell the user why. Manual opt-out stays silent.
        private func enforceLogGate() {
            if state.uploadLogs && !state.demographicsQualifyForLogs {
                state.uploadLogs = false
                logsRevoked = true
            }
        }

        var body: some View {
            Form {
                // MARK: Master toggle
                Section {
                    Toggle("Online Backup and Statistics", isOn: $state.uploadStats)
                } footer: {
                    if !state.uploadStats {
                        Text(
                            "If you enable Online Backup and Statistics, a daily backup of your settings and statistics is uploaded to open-iaps.app — letting you restore them on a new phone and contributing to the community statistics.\n\nEverything is uploaded anonymously. There is no name, email, or anything that ties the data to you — only a random recovery token stored on your phone. Off by default."
                        )
                    }
                }

                if state.uploadStats {
                    demographicsSection
                    uploadLogsSection
                    recoveryTokenSection
                    personalStatsSection
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onChange(of: state.uploadStats) {
                // Logs are meaningless without their settings — drop them with backup.
                if !state.uploadStats { state.uploadLogs = false }
            }
            .onChange(of: state.sex) {
                state.sexSetting = state.sex.saveSetting()
                enforceLogGate()
            }
            .onChange(of: state.birthDate) { enforceLogGate() }
            .onAppear {
                state.sex = Sex.savedSettings(state.sexSetting)
                if state.heightInFtIn { seedFeetInches() }
                enforceLogGate()
            }
            .alert("Why we ask about sex", isPresented: $showSexInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(
                    "Insulin sensitivity is shaped by sex hormones — estrogen and progesterone versus testosterone — not by gender identity. Choose the hormonal pattern your body currently runs on. For most people that is simply their sex; if you are on hormone therapy, choose the sex whose hormones you take.\n\nThis is used only for dosing-relevant statistics and stays anonymous."
                )
            }
            .alert("Daily Log upload turned off", isPresented: $logsRevoked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "Daily Log upload needs your sex set to Woman or Man and a valid birth date. Update your demographics to turn it back on."
                )
            }
            .navigationBarTitle("Sharing")
        }

        // MARK: - Demographics

        private var demographicsSection: some View {
            Section {
                HStack {
                    Picker("Sex", selection: $state.sex) {
                        ForEach(Sex.allCases) { sex in
                            Text(NSLocalizedString(sex.rawValue, comment: "")).tag(sex)
                        }
                    }
                    Button {
                        showSexInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                }

                DatePicker("Birth Date", selection: $state.birthDate, in: dateRange, displayedComponents: [.date])
                    .datePickerStyle(.compact)

                weightRow
                heightRow
            } header: {
                Text("Demographics")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "These values are used purely for statistics — mainly to understand how the community is distributed. It is an honor system: we have no way to verify what you enter, and no wish to. To keep the statistics meaningful we simply ask you to be honest. As with everything here, this data is anonymous."
                    )
                    Button("Why are these required for log upload?") {
                        UIApplication.shared.open(demographicsInfoURL)
                    }
                    .font(.footnote)
                }
            }
        }

        private var weightRow: some View {
            HStack {
                Text("Weight")
                Spacer()
                TextField("—", value: weightField, format: .number.precision(.fractionLength(0 ... 1)))
                    .keyboardType(.decimalPad)
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
                    TextField("ft", value: $feet, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 34)
                        .onChange(of: feet) { commitFeetInches() }
                    Text("ft").foregroundStyle(.secondary)
                    TextField("in", value: $inches, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 34)
                        .onChange(of: inches) { commitFeetInches() }
                    Text("in").foregroundStyle(.secondary)
                } else {
                    TextField("—", value: heightCmField, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
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

        // MARK: - Upload Daily Log

        private var uploadLogsSection: some View {
            Section {
                Toggle("Enable Uploads", isOn: $state.uploadLogs)
                    .disabled(!state.demographicsQualifyForLogs)
            } header: {
                Text("Upload Daily Log")
            } footer: {
                if !state.demographicsQualifyForLogs {
                    Text(
                        "Set your sex to Woman or Man and a valid birth date above to enable daily log upload."
                    )
                } else if !state.uploadLogs {
                    Text(
                        "When enabled, the previous day's log file is automatically uploaded after midnight. Logs power the multi-day analysis on open-iaps.app. Off by default."
                    )
                }
            }
        }

        // MARK: - Recovery token

        private var recoveryTokenSection: some View {
            Section {
                HStack {
                    Text(display ? state.identfier : NSLocalizedString("Tap to display", comment: "Token display button"))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .onTapGesture { display.toggle() }
                .onLongPressGesture {
                    if display {
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                        UIPasteboard.general.string = state.identfier
                        copied = true
                    }
                }
            } header: {
                Text("Your recovery token")
            } footer: {
                VStack(spacing: 6) {
                    Text((copied && display) ? "Copied" : display ? "Long press to copy" : "")
                        .foregroundStyle((display && !copied) ? .blue : .secondary)
                    Text(
                        "Write this token down somewhere safe. It is the only way to restore your settings on a new phone."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            }
        }

        private var personalStatsSection: some View {
            Section {} footer: {
                let statisticsLink = URL(string: "https://open-iaps.app/user/" + state.identfier)!
                Button("View Personal Statistics") {
                    UIApplication.shared.open(statisticsLink, options: [:], completionHandler: nil)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.system(size: 15))
            }
        }
    }
}
