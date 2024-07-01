import HealthKit
import SwiftUI
import Swinject

extension Settings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var showShareSheet = false
        @State private var token = false
        @State private var confirm = false
        @State private var next = false
        @State private var imported = false
        @State private var saved = false

        @FetchRequest(
            entity: VNr.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)], predicate: NSPredicate(
                format: "nr != %@", "" as String
            )
        ) var fetchedVersionNumber: FetchedResults<VNr>

        var body: some View {
            if state.firstRun {
                onboardingView
            } else {
                settingsView
            }
        }

        var settingsView: some View {
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
                    Text("Basal Profile").navigationLink(to: .basalProfileEditor, from: self)
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
                    Text("Dynamic ISF").navigationLink(to: .dynamicISF, from: self)
                    Text("Sharing").navigationLink(to: .sharing, from: self)
                    Text("Contact Image").navigationLink(to: .contactTrick, from: self)
                } header: { Text("Extra Features") }

                Section {
                    Toggle("Debug options", isOn: $state.debugOptions)
                    if state.debugOptions {
                        Group {
                            HStack {
                                Text("Upload Profile and Settings")
                                Button("Upload") { state.uploadProfileAndSettings(true) }
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .buttonStyle(.borderedProminent)
                            }
                            /*
                             HStack {
                             Text("Delete All NS Overrides")
                             Button("Delete") { state.deleteOverrides() }
                             .frame(maxWidth: .infinity, alignment: .trailing)
                             .buttonStyle(.borderedProminent)
                             .tint(.red)
                             }*/

                            HStack {
                                Toggle("Ignore flat CGM readings", isOn: $state.disableCGMError)
                            }

                            HStack {
                                Text("Start Onboarding")
                                Button("Start") {
                                    reset()
                                    state.firstRun = true
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .buttonStyle(.borderedProminent)
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

        private var onboardingView: some View {
            Form {
                if !token {
                    onboarding
                } else if !imported {
                    tokenView
                    if state.token != "" {
                        startImportView
                    }
                } else if !next {
                    importedView
                } else if !confirm {
                    fetchingView
                    listFetchedView
                } else if saved {
                    savedView
                }

            }.onAppear(perform: configureView)
                .navigationTitle("Onboarding")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(trailing: Button("Cancel") {
                    reset()
                    onBoardingDone()
                })
        }

        private var onboarding: some View {
            Section {
                HStack {
                    Button { token.toggle() }
                    label: {
                        Text("Yes")
                    }.buttonStyle(.borderless)
                        .padding(.leading, 10)

                    Spacer()

                    Button {
                        state.close()
                        state.onboardingDone()
                    }
                    label: {
                        Text("No")
                    }
                    .buttonStyle(.borderless)
                    .tint(.red)
                    .padding(.trailing, 10)
                }
            } header: {
                VStack {
                    Text("Welcome to iAPS, v\(state.versionNumber)!")
                        .font(.previewHeadline).frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 40)

                    Text("Do you have any settings you want to import?\n").font(.previewNormal)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .textCase(nil)
                .foregroundStyle(.primary)
            }
            footer: {
                Text(
                    "\n\nIf you've previously made any backup of your settings and statistics to the online database you now can choose to import all of these settings to iAPS using your recovery token. The recovery token you can find in your old iAPS app in the Sharing settings.\n\nIf you don't have any settings saved to import make sure to enable the setting \"Share all statistics\" in the Sharing settings later, as this will enable daily auto backups of your current settings and statistics."
                )
                .textCase(nil)
                .font(.previewNormal)
            }
        }

        private var tokenView: some View {
            Section {
                TextField("Token", text: $state.token)
            }
            header: {
                Text("Enter your recovery token").foregroundStyle(.primary).textCase(nil).font(.previewNormal)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            footer: {
                Text("\nThe recovery token you can find on your old phone in the Sharing settings.")
                    .textCase(nil)
                    .font(.previewNormal)
            }
        }

        private var startImportView: some View {
            Section {
                Button {
                    state.importSettings(id: state.token)
                    imported.toggle()
                }
                label: {
                    Text("Start import").frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(!(state.token == "") ? Color(.systemBlue) : Color(.systemGray4))
                .tint(.white)
            }
        }

        private var fetchingView: some View {
            Section {} header: {
                Text(
                    "\nFetching done. Now please scroll down and check that all of your fetched settings below are correct, before saving."
                )
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .textCase(nil)
                .font(.previewNormal)
            }
        }

        private var listFetchedView: some View {
            Group {
                if let profiles = state.profiles {
                    if let defaultProfiles = profiles.store["default"] {
                        // Basals
                        let basals_ = defaultProfiles.basal.map({
                            basal in
                            BasalProfileEntry(
                                start: basal.time + ":00",
                                minutes: state.offset(basal.time) / 60,
                                rate: basal.value
                            )
                        })

                        let units: String = state.freeapsSettings?.units.rawValue ?? "mmol/l"

                        Section {
                            ForEach(basals_, id: \.start) { item in
                                HStack {
                                    Text(item.start)
                                    Spacer()
                                    Text(item.rate.formatted())
                                    Text("U/h")
                                }
                            }
                        } header: {
                            Text("Basals")
                        }

                        // CRs
                        Section {
                            let crs_ = defaultProfiles.carbratio.map({
                                cr in
                                CarbRatioEntry(start: cr.time, offset: (cr.timeAsSeconds ?? 0) / 60, ratio: cr.value)
                            })
                            ForEach(crs_, id: \.start) { item in
                                HStack {
                                    Text(item.start)
                                    Spacer()
                                    Text(item.ratio.formatted())
                                    Text("g/U")
                                }
                            }
                        } header: { Text("Carb Ratios") }

                        // ISFs
                        Section {
                            let isfs_ = defaultProfiles.sens.map({
                                isf in
                                InsulinSensitivityEntry(
                                    sensitivity: isf.value,
                                    offset: (isf.timeAsSeconds ?? 0) / 60,
                                    start: isf.time
                                )
                            })

                            ForEach(isfs_, id: \.start) { item in
                                HStack {
                                    Text(item.start)
                                    Spacer()
                                    Text(item.sensitivity.formatted())
                                    Text(units + "/U")
                                }
                            }
                        } header: {
                            Text("Insulin Sensitivities")
                        }

                        // Targets
                        Section {
                            let targets_ = defaultProfiles.target_low.map({
                                target in
                                BGTargetEntry(
                                    low: target.value,
                                    high: target.value,
                                    start: target.time,
                                    offset: (target.timeAsSeconds ?? 0) / 60
                                )
                            })

                            ForEach(targets_, id: \.start) { item in
                                HStack {
                                    Text(item.start)
                                    Spacer()
                                    Text(item.low.formatted())
                                    Text(units)
                                }
                            }
                        } header: { Text("Targets") }
                    }
                }

                // iAPS Settings
                if let freeapsSettings = state.freeapsSettings {
                    Section {
                        Text(trim(freeapsSettings.rawJSON.debugDescription)).font(.previewSmall)
                    } header: {
                        Text("iAPS Settings")
                    }
                }

                // OpenAPS Settings
                if let settings = state.settings {
                    Section {
                        Text(trim(settings.rawJSON.debugDescription)).font(.previewSmall)
                    } header: {
                        Text("OpenAPS Settings")
                    }
                }

                // Save
                Button {
                    state.save()
                    saved.toggle()
                    confirm.toggle()
                }
                label: {
                    Text("Save settings")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color(.systemBlue))
                .tint(.white)
            }
        }

        private var importedView: some View {
            Group {
                Section {
                    HStack {
                        Text("Basals")
                        Spacer()
                        Text(state.basalsOK ? "OK" : "Not imported")
                            .foregroundStyle(state.basalsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Carb Ratios")
                        Spacer()
                        Text(state.crsOK ? "OK" : "Not imported")
                            .foregroundStyle(state.crsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Insulin Sensitivites")
                        Spacer()
                        Text(state.isfsOK ? "OK" : "Not imported")
                            .foregroundStyle(state.isfsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Targets")
                        Spacer()
                        Text(state.targetsOK ? "OK" : "Not imported")
                            .foregroundStyle(state.targetsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Preferences")
                        Spacer()
                        Text(state.settingsOK ? "OK" : "Not imported")
                            .foregroundStyle(state.settingsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("iAPS Settings")
                        Spacer()
                        Text(state.freeapsSettingsOK ? "OK" : "Not imported")
                            .foregroundStyle(state.freeapsSettingsOK ? Color(.darkGreen) : .red)
                    }
                } header: {
                    Text("Fetched settings").font(.previewNormal)
                }

                Button {
                    next.toggle()
                }
                label: {
                    Text("Continue")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color(.systemBlue))
                .tint(.white)
            }
        }

        private var savedView: some View {
            Group {
                Section {
                    HStack {
                        Text("Basals")
                        Spacer()
                        Text(state.basalsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(state.basalsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Carb Ratios")
                        Spacer()
                        Text(state.crsOKSaved ? "Saved" : "Not saved")
                            .foregroundStyle(state.crsOKSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Insulin Sensitivites")
                        Spacer()
                        Text(state.isfsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(state.isfsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Targets")
                        Spacer()
                        Text(state.targetsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(state.targetsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Preferences")
                        Spacer()
                        Text(state.settingsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(state.settingsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("iAPS Settings")
                        Spacer()
                        Text(state.freeapsSettingsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(state.freeapsSettingsSaved ? Color(.darkGreen) : .red)
                    }
                } header: {
                    Text("Saved settings").font(.previewNormal)
                }

                Button {
                    reset()
                    onBoardingDone()
                }
                label: {
                    Text("OK")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color(.systemBlue))
                .tint(.white)
            }
        }

        private func reset() {
            saved = false
            confirm = false
            imported = false
            token = false
            next = false
        }

        private func onBoardingDone() {
            state.firstRun = false
        }

        private func trim(_ string: String) -> String {
            let trim = string
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\n", with: "")
                .replacingOccurrences(of: "\\", with: "")
                .replacingOccurrences(of: "}", with: "")
                .replacingOccurrences(of: "{", with: "")
                .replacingOccurrences(
                    of: "\"",
                    with: "",
                    options: NSString.CompareOptions.literal,
                    range: nil
                )
                .replacingOccurrences(of: "[", with: "\n")
                .replacingOccurrences(of: "]", with: "\n")
                .replacingOccurrences(of: "dia", with: "DIA")
            let data = trim.components(separatedBy: ",").sorted { $0.count < $1.count }
                .debugDescription.replacingOccurrences(of: ",", with: "\n")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "\"", with: "")

            return data
        }
    }
}
