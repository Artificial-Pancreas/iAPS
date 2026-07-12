import CoreData
import SwiftUI
import Swinject

extension NightscoutConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let appCoordinator: AppCoordinator
        @StateObject var state: StateModel
        @State var importAlert: Alert?
        @State var isImportAlertPresented = false
        @State var importedHasRun = false
        @State var displayPopUp = false
        @State var editedScheduleGroup: UploadScheduleGroup?
        @State var lastUploadsShown = false

        @FetchRequest(
            entity: ImportError.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "date > %@", Date().subtractingTimeInterval(.minutes(1)) as NSDate
            )
        ) var fetchedErrors: FetchedResults<ImportError>

        init(resolver: Resolver) {
            self.resolver = resolver
            appCoordinator = resolver.resolve(AppCoordinator.self)!
            _state = StateObject(wrappedValue: StateModel(resolver: resolver))
        }

        private var portFormater: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.allowsFloats = false
            return formatter
        }

        private var daysFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private func uploadScheduleRow(_ group: UploadScheduleGroup, schedule: UploadSchedule) -> some View {
            Button { editedScheduleGroup = group } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.displayName).foregroundStyle(Color.primary)
                        Text(scheduleDescription(schedule))
                            .font(.caption)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }

        private func scheduleDescription(_ schedule: UploadSchedule) -> String {
            [
                String(
                    format: NSLocalizedString("Wi-Fi: %@", comment: "Upload schedule summary"),
                    networkDescription(schedule.onWifi)
                ),
                String(
                    format: NSLocalizedString("Mobile data: %@", comment: "Upload schedule summary"),
                    networkDescription(schedule.onCellular)
                )
            ].joined(separator: "\n")
        }

        private func networkDescription(_ network: UploadNetworkSchedule) -> String {
            if network.interval != .always, network.alwaysWhileCharging {
                return String(
                    format: NSLocalizedString("%@ (always while charging)", comment: "Upload schedule summary"),
                    network.interval.displayName
                )
            }
            return network.interval.displayName
        }

        private func scheduleBinding(for group: UploadScheduleGroup) -> Binding<UploadSchedule> {
            switch group {
            case .glucose: return $state.glucoseUploadSchedule
            case .treatmentsAndLoops: return $state.treatmentsAndLoopsUploadSchedule
            case .deviceStatus: return $state.deviceStatusUploadSchedule
            }
        }

        var body: some View {
            Form {
                Section {
                    TextField("URL", text: $state.url)
                        .disableAutocorrection(true)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    SecureField("API secret", text: $state.secret)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .textContentType(.password)
                        .keyboardType(.asciiCapable)
                    if !state.message.isEmpty {
                        Text(state.message)
                    }
                    if state.connecting {
                        HStack {
                            Text("Connecting...")
                            Spacer()
                            ProgressView()
                        }
                    }
                }

                Section {
                    Button("Connect") { state.connect() }
                        .disabled(state.url.isEmpty || state.connecting)
                    Button("Delete") { state.delete() }.foregroundColor(.red).disabled(state.connecting)
                }

                Section {
                    Toggle("Upload", isOn: $state.isUploadEnabled)
                    if state.isUploadEnabled {
                        uploadScheduleRow(.glucose, schedule: state.glucoseUploadSchedule)
                        uploadScheduleRow(.treatmentsAndLoops, schedule: state.treatmentsAndLoopsUploadSchedule)
                        uploadScheduleRow(.deviceStatus, schedule: state.deviceStatusUploadSchedule)
                    }
                } header: {
                    HStack {
                        Text("Allow Uploads")
                        if state.isUploadEnabled {
                            Spacer()
                            Button { lastUploadsShown = true } label: {
                                Image(systemName: "info.circle")
                            }
                        }
                    }
                } footer: {
                    if state.isUploadEnabled {
                        Text(
                            "Upload schedules limit how often each data group is uploaded to Nightscout to reduce battery usage. Postponed data is uploaded later in one batch."
                        )
                    }
                }

                if state.cgmDisablesGlucoseUpload, state.isUploadEnabled {
                    Section {
                        HStack {
                            Text("Glucose upload disabled in CGM settings").foregroundStyle(.red)
                        }
                    }
                }

                Section {
                    Toggle("Fetch", isOn: $state.nightscoutFetchEnabled)
                } header: {
                    Text("Allow Fetching")
                } footer: {
                    Text("iAPS will fetch announcements, carbs and temp targets from Nightscout")
                }

                Section {
                    Button("Import settings from Nightscout") {
                        importAlert = Alert(
                            title: Text("Import settings?"),
                            message: Text(
                                "\n" +
                                    NSLocalizedString(
                                        "This will replace some or all of your current pump settings. Are you sure you want to import profile settings from Nightscout?",
                                        comment: "Profile Import Alert"
                                    ) +
                                    "\n"
                            ),
                            primaryButton: .destructive(
                                Text("Yes, Import"),
                                action: {
                                    state.importSettings()
                                    importedHasRun = true
                                }
                            ),
                            secondaryButton: .cancel()
                        )
                        isImportAlertPresented.toggle()
                    }.disabled(state.url.isEmpty || state.connecting)

                } header: { Text("Import from Nightscout") }

                    .alert(isPresented: $importedHasRun) {
                        Alert(
                            title: Text((fetchedErrors.first?.error ?? "").count < 4 ? "Settings imported" : "Import Error"),
                            message: Text(
                                (fetchedErrors.first?.error ?? "").count < 4 ?
                                    NSLocalizedString(
                                        "\nNow please verify all of your new settings thoroughly:\n\n* Basal Settings\n * Carb Ratios\n * Glucose Targets\n * Insulin Sensitivities\n * DIA\n\n in iAPS Settings > Configuration.\n\nBad or invalid profile settings could have disatrous effects.",
                                        comment: "Imported Profiles Alert"
                                    ) :
                                    NSLocalizedString(fetchedErrors.first?.error ?? "", comment: "Import Error")
                            ),
                            primaryButton: .destructive(
                                Text("OK")
                            ),
                            secondaryButton: .cancel()
                        )
                    }

                Section {
                    HStack {
                        Text("Days").foregroundStyle(.secondary)
                        Spacer()
                        DecimalTextField("1", value: $state.backFillInterval, formatter: daysFormatter, liveEditing: true)
                    }
                    if state.backfilling {
                        ProgressView(value: min(max(state.backfillingProgress, 0), 1), total: 1.0)
                            .progressViewStyle(BackfillProgressViewStyle())
                    }
                    Button("Backfill glucose") { state.backfillGlucose() }
                        .disabled(state.url.isEmpty || state.connecting || state.backfilling)
                }
                header: { Text("Backfill glucose") }
                footer: { Text("Fetches old glucose readings from Nightscout") }

                if state.isUploadEnabled, state.cgmEnablesGlucoseUpload {
                    Section {
                        HStack {
                            Text("Days").foregroundStyle(.secondary)
                            Spacer()
                            DecimalTextField("1", value: $state.uploadInterval, formatter: daysFormatter, liveEditing: true)
                        }
                        if state.uploading {
                            ProgressView(value: min(max(state.uploadingProgress, 0), 1), total: 1.0)
                                .progressViewStyle(BackfillProgressViewStyle())
                        }
                        Button("Upload glucose") { state.uploadOldGlucose() }
                            .disabled(state.url.isEmpty || state.connecting || state.uploading)
                    }
                    header: { Text("Upload glucose") }
                    footer: { Text("Uploads old glucose readings to Nightscout") }
                }

                Section {
                    Toggle("Remote control", isOn: $state.allowAnnouncements)
                } header: { Text("Allow Remote control of iAPS") }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .navigationBarTitle("Nightscout Config")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(isPresented: $isImportAlertPresented) {
                importAlert!
            }
            .sheet(item: $editedScheduleGroup) { group in
                UploadScheduleEditor(title: group.displayName, schedule: scheduleBinding(for: group))
            }
            .sheet(isPresented: $lastUploadsShown) {
                LastUploadsView()
            }
        }
    }
}

extension NightscoutConfig {
    struct LastUploadsView: View {
        @Environment(\.dismiss) private var dismiss

        // names must match the gate names of the NightscoutUploads entities
        private static let entities: [(name: String, label: String)] = [
            ("glucose", NSLocalizedString("Glucose", comment: "Upload entity")),
            ("pumpHistory", NSLocalizedString("Pump history", comment: "Upload entity")),
            ("carbs", NSLocalizedString("Carbs", comment: "Upload entity")),
            ("tempTargets", NSLocalizedString("Temp targets", comment: "Upload entity")),
            ("loopStatus", NSLocalizedString("Loop status", comment: "Upload entity")),
            ("overrides", NSLocalizedString("Overrides", comment: "Upload entity")),
            ("podAge", NSLocalizedString("Pod age", comment: "Upload entity")),
            ("cgmState", NSLocalizedString("CGM state", comment: "Upload entity")),
            ("pumpStatus", NSLocalizedString("Pump status", comment: "Upload entity")),
            ("iob", NSLocalizedString("IOB", comment: "Upload entity"))
        ]

        var body: some View {
            NavigationStack {
                Form {
                    ForEach(Self.entities, id: \.name) { entity in
                        HStack {
                            Text(entity.label)
                            Spacer()
                            if let lastUpload = UploadScheduleGate.lastUpload(named: entity.name) {
                                Text(lastUpload.formatted(date: .abbreviated, time: .shortened))
                                    .foregroundStyle(Color.secondary)
                            } else {
                                Text("Never").foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle("Last Uploads")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    struct UploadScheduleEditor: View {
        let title: String
        @Binding var schedule: UploadSchedule
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Picker("Upload", selection: $schedule.onWifi.interval) {
                            ForEach(UploadScheduleInterval.wifiCases) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        if schedule.onWifi.interval != .always {
                            Toggle("Always upload while charging", isOn: $schedule.onWifi.alwaysWhileCharging)
                        }
                    } header: {
                        Text("On Wi-Fi")
                    }

                    Section {
                        Picker("Upload", selection: $schedule.onCellular.interval) {
                            ForEach(UploadScheduleInterval.allCases) { interval in
                                Text(interval.displayName).tag(interval)
                            }
                        }
                        if schedule.onCellular.interval != .always {
                            Toggle("Always upload while charging", isOn: $schedule.onCellular.alwaysWhileCharging)
                        }
                    } header: {
                        Text("On mobile data")
                    } footer: {
                        Text("Data that is not uploaded right away is kept and uploaded when the schedule next allows it.")
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}

public struct BackfillProgressViewStyle: ProgressViewStyle {
    @Environment(\.colorScheme) var colorScheme

    public func makeBody(configuration: LinearProgressViewStyle.Configuration) -> some View {
        @State var progress = CGFloat(configuration.fractionCompleted ?? 0)
        ZStack {
            ProgressView(value: progress)
                .tint(Color.loopGreen)
                .scaleEffect(y: 5.5)
                .frame(height: 10)
        }
    }
}
