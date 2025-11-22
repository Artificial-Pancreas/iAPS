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

        @FetchRequest(
            entity: ImportError.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "date > %@", Date().addingTimeInterval(-1.minutes.timeInterval) as NSDate
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
                } header: {
                    Text("Allow Uploads")
                }

                if let cgmManager = state.deviceManager.cgmManager,
                   KnownPlugins.glucoseUploadingAvailable(for: cgmManager),
                   !cgmManager.shouldSyncToRemoteService,
                   state.isUploadEnabled
                {
                    Section {
                        HStack {
                            Text("Glucose upload disabled in CGM settings").foregroundStyle(.red)
                        }
                    }
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

                if state.isUploadEnabled, appCoordinator.shouldUploadGlucose {
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
