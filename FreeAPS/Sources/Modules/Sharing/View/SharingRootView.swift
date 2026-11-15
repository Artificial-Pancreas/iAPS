import SwiftUI
import Swinject

public enum Sex: String, CaseIterable, Identifiable {
    case woman = "Woman"
    case man = "Man"
    case other = "Other"
    /// stored as 3, the default (was "Prefer not to say")
    case secret = "Not set"
    public var id: Self { self }

    var displayName: String {
        switch self {
        case .woman: return NSLocalizedString("Woman", comment: "Sex dropdown menu option")
        case .man: return NSLocalizedString("Man", comment: "Sex dropdown menu option")
        case .other: return NSLocalizedString("Other", comment: "Sex dropdown menu option")
        case .secret: return NSLocalizedString("Not set", comment: "Sex dropdown menu option: none chosen")
        }
    }

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
        /// pushed from Settings › Demographics: "Edit in Settings › About You" goes back there instead of pushing it again
        let fromDemographics: Bool
        @StateObject var state: StateModel

        @Environment(\.dismiss) private var dismiss

        @State private var display: Bool = false
        @State private var copied: Bool = false
        @State private var showCrashInfo: Bool = false
        @State private var logsRevoked: Bool = false
        /// Shown, not covered by a screen pushed over it (Settings › Demographics, where a change can revoke the logs)
        @State private var isShown: Bool = false
        /// Revoked while covered: told when shown again (an alert raised under a pushed screen isn't seen)
        @State private var logsRevokedUnseen: Bool = false

        private let demographicsInfoURL = URL(string: "https://open-iaps.app/demographics")!

        init(resolver: Resolver, fromDemographics: Bool = false) {
            self.resolver = resolver
            self.fromDemographics = fromDemographics
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        /// Auto-revoke Daily Log upload the moment the demographics stop qualifying,
        /// and tell the user why. Manual opt-out stays silent. Also once `uploadLogs` is read from the settings
        /// (`subscribe()`, after the screen appeared): on at the start while not qualifying is turned off then.
        private func enforceLogGate() {
            if state.uploadLogs, !state.demographicsQualifyForLogs {
                state.uploadLogs = false
                if isShown {
                    logsRevoked = true
                } else {
                    logsRevokedUnseen = true
                }
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
                    shareDemographicsSection
                    uploadLogsSection
                    recoveryTokenSection
                    personalStatsSection
                }

                crashReportsSection
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onChange(of: state.uploadStats) {
                // Logs are meaningless without their settings — drop them with backup.
                if !state.uploadStats { state.uploadLogs = false }
            }
            .onChange(of: state.demographics) { enforceLogGate() }
            // the toggle is disabled while not qualifying: a change while not qualifying is the settings' value
            // arriving, never the user turning it on
            .onChange(of: state.uploadLogs) { enforceLogGate() }
            .onAppear {
                isShown = true
                if logsRevokedUnseen {
                    logsRevokedUnseen = false
                    logsRevoked = true
                }
                enforceLogGate()
                // Seeing this screen counts as having been offered crash reporting; the
                // upgrade path re-shows Sharing once for users who predate the option.
                UserDefaults.standard.set(true, forKey: IAPSconfig.hasSeenCrashReportOption)
            }
            .onDisappear { isShown = false }
            .alert("What a crash report contains", isPresented: $showCrashInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text(
                    "When iAPS crashes, a report is saved on your phone and sent to open-iaps.app the next time the app starts. It contains the code path that crashed (function names and addresses), the state of each thread, the error message the app stopped with, your phone model, iOS version and iAPS version.\n\nIt does not contain glucose readings, insulin or settings; the raw memory KSCrash captures is removed before anything is sent. It is filed under the same anonymous id as statistics.\n\nReports are only sent from the latest main and dev releases — older versions may crash on bugs already fixed. Nothing else needs to be turned on for this to help."
                )
            }
            .alert("Daily Log upload turned off", isPresented: $logsRevoked) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "Daily Log upload needs your sex (Woman or Man) and your age shared. Turn it back on once they are."
                )
            }
            .navigationBarTitle("Sharing")
        }

        // MARK: - Share demographics (the values are set in Settings › Demographics)

        private var shareDemographicsSection: some View {
            Section {
                shareRow(
                    "Sex",
                    value: state.demographics.isSexSet ? Sex.savedSettings(state.sexSetting).displayName : nil,
                    isOn: $state.shareSex
                )
                shareRow(
                    "Age",
                    value: Demographics.bornText(state.birthDate),
                    isOn: $state.shareAge
                )
                editInDemographicsRow
            } header: {
                Text("Share sex and age")
            } footer: {
                Text(
                    "These toggles set what the daily statistics include. The settings backup includes your sex, birth date, weight and height either way."
                )
            }
        }

        /// To Settings › Demographics, or back to it when pushed from there (no Demographics › Sharing › … chain).
        @ViewBuilder private var editInDemographicsRow: some View {
            let label = Text("Edit in Settings › About You").foregroundStyle(Color.accentColor)
            if fromDemographics {
                Button { dismiss() } label: { label }
            } else {
                label.navigationLink(to: .demographics(fromSharing: true), from: self)
            }
        }

        /// A value and its share toggle; without the value (nil) "Not set" and the toggle off and disabled.
        private func shareRow(_ title: LocalizedStringKey, value: String?, isOn: Binding<Bool>) -> some View {
            Toggle(isOn: Binding(get: { value != nil && isOn.wrappedValue }, set: { isOn.wrappedValue = $0 })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(value ?? NSLocalizedString("Not set", comment: "Sharing: a demographic value not set"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(value == nil)
        }

        // MARK: - Upload Daily Log

        private var uploadLogsSection: some View {
            Section {
                Toggle("Enable Uploads", isOn: $state.uploadLogs)
                    .disabled(!state.demographicsQualifyForLogs)
            } header: {
                Text("Upload Daily Log")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if state.demographicsQualifyForLogs {
                        Text("The previous day’s log is uploaded after midnight.")
                    } else {
                        Text("Needs sex (Woman or Man) and age shared above.")
                    }
                    Button("Why are these required for log upload?") {
                        UIApplication.shared.open(demographicsInfoURL)
                    }
                    .font(.footnote)
                }
            }
        }

        // MARK: - Crash reports (independent of the other sharing toggles)

        private var crashReportsSection: some View {
            Section {
                HStack {
                    Toggle("Send crash reports", isOn: $state.uploadCrashReports)
                    Button {
                        showCrashInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Crash Reports")
            } footer: {
                Text(
                    "If iAPS crashes, send the developers a report of where it happened. Anonymous, no glucose or settings. Off by default."
                )
            }
        }

        // MARK: - Recovery token

        private var recoveryTokenSection: some View {
            Section {
                HStack {
                    Text(display ? state.identifier : NSLocalizedString("Tap to display", comment: "Token display button"))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .onTapGesture { display.toggle() }
                .onLongPressGesture {
                    if display {
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                        UIPasteboard.general.string = state.identifier
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
                let statisticsLink = URL(string: "https://open-iaps.app/user/" + state.identifier)!
                Button("View Personal Statistics") {
                    UIApplication.shared.open(statisticsLink, options: [:], completionHandler: nil)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .font(.system(size: 15))
            }
        }
    }
}
