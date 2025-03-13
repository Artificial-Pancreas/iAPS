import HealthKit
import SwiftUI
import Swinject

extension Settings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showShareSheet = false

        @FetchRequest(
            entity: VNr.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "nr != %@", "" as String
            )
        ) var fetchedVersionNumber: FetchedResults<VNr>

        @FetchRequest(
            entity: OverridePresets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)], predicate: NSPredicate(
                format: "name != %@", "" as String
            )
        ) var fetchedProfiles: FetchedResults<OverridePresets>

        var body: some View {
            Form {
                Section {
                    Toggle("Closed loop", isOn: $state.closedLoop)
                }
                header: {
                    VStack(alignment: .leading) {
                        if let expirationDate = Bundle.main.profileExpiration {
                            Text(
                                "iAPS v\(state.versionNumber) (\(state.buildNumber))\nBranch: \(state.branch) \(state.copyrightNotice)" +
                                    "\nBuild Expires: " + expirationDate
                            ).textCase(nil)
                        } else {
                            Text(
                                "iAPS v\(state.versionNumber) (\(state.buildNumber))\nBranch: \(state.branch) \(state.copyrightNotice)"
                            )
                        }

                        if let latest = fetchedVersionNumber.first,
                           ((latest.nr ?? "") > state.versionNumber) ||
                           ((latest.nr ?? "") < state.versionNumber && (latest.dev ?? "") > state.versionNumber)
                        {
                            Text(
                                "Latest version on GitHub: " +
                                    ((latest.nr ?? "") < state.versionNumber ? (latest.dev ?? "") : (latest.nr ?? "")) + "\n"
                            )
                            .foregroundStyle(.orange).bold()
                            .multilineTextAlignment(.leading)
                        }
                    }
                }

                Section {
                    Text("Pump").navigationLink(to: .pumpConfig, from: self)
                    Text("CGM").navigationLink(to: .cgm, from: self)
                    Text("Watch").navigationLink(to: .watch, from: self)
                } header: { Text("Devices") }

                Section {
                    Text("Nightscout").navigationLink(to: .nighscoutConfig, from: self)
                    if HKHealthStore.isHealthDataAvailable() {
                        Text("Apple Health").navigationLink(to: .healthkit, from: self)
                    }
                    Text("Notifications").navigationLink(to: .notificationsConfig, from: self)
                } header: { Text("Services") }

                Section {
                    Text("Pump Settings").navigationLink(to: .pumpSettingsEditor, from: self)
                    Text("Basal Profile").navigationLink(to: .basalProfileEditor(saveNewConcentration: false), from: self)
                    Text("Insulin Sensitivities").navigationLink(to: .isfEditor, from: self)
                    Text("Carb Ratios").navigationLink(to: .crEditor, from: self)
                    Text("Target Glucose").navigationLink(to: .targetsEditor, from: self)
                } header: { Text("Configuration") }

                Section {
                    Text("OpenAPS").navigationLink(to: .preferencesEditor, from: self)
                    Text("Autotune").navigationLink(to: .autotuneConfig, from: self)
                } header: { Text("OpenAPS") }

                Section {
                    Text("UI/UX").navigationLink(to: .statisticsConfig, from: self)
                    Text("App Icons").navigationLink(to: .iconConfig, from: self)
                    Text("Bolus Calculator").navigationLink(to: .bolusCalculatorConfig, from: self)
                    Text("Fat And Protein Conversion").navigationLink(to: .fpuConfig, from: self)
                    Text("Sharing").navigationLink(to: .sharing, from: self)
                    Text("Contact Image").navigationLink(to: .contactTrick, from: self)
                    Text("Dynamic ISF").navigationLink(to: .dynamicISF, from: self)
                    Text("Auto ISF").navigationLink(to: .autoISF, from: self)
                } header: { Text("Extra Features") }

                Section {
                    HStack {
                        Picker("Treatment", selection: $state.profileID) {
                            Text("Default  📉").tag("Hypo Treatment")
                            ForEach(fetchedProfiles) { item in
                                Text(item.name ?? "").tag(item.id?.string ?? "")
                            }
                            Text("None").tag("None")
                        }
                    }
                } header: { Text("Hypo Treatment") }

                Section {
                    Toggle("Debug options", isOn: $state.debugOptions)
                    if state.debugOptions {
                        Group {
                            HStack {
                                Text("NS Upload Profile and Settings")
                                Button("Upload") { state.uploadProfileAndSettings(true) }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .buttonStyle(.borderedProminent)
                            }

                            // Test code
                            HStack {
                                Text("Delete All NS Overrides")
                                Button("Delete") { state.deleteOverrides() }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                            }

                            HStack {
                                Toggle("Ignore flat CGM readings", isOn: $state.disableCGMError)
                            }

                            HStack {
                                Toggle("Allow diluted insulin concentration settings", isOn: $state.allowDilution)
                            }

                            HStack {
                                Toggle("Max Override 400%", isOn: $state.extended_overrides)
                            }
                        }
                        Group {
                            Text("Preferences")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.preferences), from: self)
                            Text("Pump Settings")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.settings), from: self)
                            Text("Autosense")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autosense), from: self)
                            Text("Pump History")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.pumpHistory), from: self)
                            Text("Temp Basals")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.tempBasal), from: self)
                            Text("Basal profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.basalProfile), from: self)
                            Text("Targets ranges")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.bgTargets), from: self)
                            Text("Temp targets")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.tempTargets), from: self)
                            Text("Meal")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.meal), from: self)
                        }

                        Group {
                            Text("Pump profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.pumpProfile), from: self)
                            Text("Profile")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.profile), from: self)
                            Text("Carbs")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.carbHistory), from: self)
                            Text("Enacted")
                                .navigationLink(to: .configEditor(file: OpenAPS.Enact.enacted), from: self)
                            Text("Announcements")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcements), from: self)
                            Text("Enacted announcements")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.announcementsEnacted), from: self)
                            Text("Overrides Not Uploaded")
                                .navigationLink(to: .configEditor(file: OpenAPS.Nightscout.notUploadedOverrides), from: self)
                            Text("Autotune")
                                .navigationLink(to: .configEditor(file: OpenAPS.Settings.autotune), from: self)
                            Text("Glucose")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.glucose), from: self)
                        }

                        Group {
                            Text("Dynamic Variables")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.dynamicVariables), from: self)
                        }

                        Group {
                            Text("Target presets")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.tempTargetsPresets), from: self)
                            Text("Calibrations")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.calibrations), from: self)
                            Text("Middleware")
                                .navigationLink(to: .configEditor(file: OpenAPS.Middleware.determineBasal), from: self)
                            Text("Statistics")
                                .navigationLink(to: .configEditor(file: OpenAPS.Monitor.statistics), from: self)
                            Text("Edit settings json")
                                .navigationLink(to: .configEditor(file: OpenAPS.FreeAPS.settings), from: self)
                        }
                    }
                } header: { Text("Developer") }

                Section {
                    Toggle("Animated Background", isOn: $state.animatedBackground)
                }

                Section {
                    Text("Share logs")
                        .onTapGesture {
                            showShareSheet = true
                        }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: state.logItems())
            }
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Close", action: state.hideSettingsModal))
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear(perform: { state.uploadProfileAndSettings(false) })
        }
    }
}
