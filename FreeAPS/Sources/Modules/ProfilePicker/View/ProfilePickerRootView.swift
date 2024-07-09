import LoopKit
import SwiftUI
import Swinject

extension ProfilePicker {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @Environment(\.dismiss) private var dismiss

        @Binding var int: Int
        @Binding var profile: String
        @Binding var inSitu: Bool
        @Binding var id_: String

        @State var basals: [BasalProfileEntry]?
        @State var basalsOK: Bool = false
        @State var basalsSaved: Bool = false

        @State var crs: [CarbRatioEntry]?
        @State var crsOK: Bool = false
        @State var crsOKSaved: Bool = false

        @State var isfs: [InsulinSensitivityEntry]?
        @State var isfsOK: Bool = false
        @State var isfsSaved: Bool = false

        @State var settings: Preferences?
        @State var settingsOK: Bool = false
        @State var settingsSaved: Bool = false

        @State var freeapsSettings: FreeAPSSettings?
        @State var freeapsSettingsOK: Bool = false
        @State var freeapsSettingsSaved: Bool = false

        @State var profiles: NightscoutProfileStore?
        @State var profilesOK: Bool = false

        @State var targets: BGTargetEntry?
        @State var targetsOK: Bool = false
        @State var targetsSaved: Bool = false

        @State var tempTargets: [TempTarget]?
        @State var tempTargetsOK: Bool = false
        @State var tempTargetsSaved: Bool = false

        @State var pumpSettings: PumpSettings?
        @State var pumpSettingsOK: Bool = false
        @State var pumpSettingsSaved: Bool = false
        @State var diaOK: Bool = false
        @State var diaSaved: Bool = false

        @State var firstRun = false
        @State var imported = false
        @State var viewInt = 0

        var fetchedVersionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        @State var token: String = ""

        @State var lifetime = Lifetime()

        var GlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if viewInt == 0 {
                    onboarding
                } else if viewInt == 1 {
                    tokenView
                    if token != "" {
                        startImportView
                    }
                } else if viewInt == 2 {
                    importedView
                } else if viewInt == 3 {
                    fetchingView
                    listFetchedView
                } else if viewInt == 4 {
                    savedView
                }
            }
            .navigationTitle("Onboarding")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                reset()
                onboardingDone()
            })
            .navigationBarItems(leading: viewInt > 0 ? Button("Back") { viewInt -= 1 } : nil)
            .onAppear {
                viewInt = int
                if inSitu {
                    importSettings(id: id_)
                }
            }
        }

        private var onboarding: some View {
            Section {
                HStack {
                    Button { viewInt += 1 }
                    label: { Text("Yes") }
                        .buttonStyle(.borderless)
                        .padding(.leading, 10)

                    Spacer()

                    Button {
                        close()
                        onboardingDone()
                    }
                    label: { Text("No") }
                        .buttonStyle(.borderless)
                        .tint(.red)
                        .padding(.trailing, 10)
                }
            } header: {
                VStack {
                    Text("Welcome to iAPS, v\(fetchedVersionNumber)!")
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
                TextField("Token", text: $token)
            }
            header: {
                Text("Enter your recovery token")
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
                    importSettings(id: token)
                    viewInt += 1
                }
                label: {
                    Text("Start import").frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(!(token == "") ? Color(.systemBlue) : Color(.systemGray4))
                .tint(.white)
            }
        }

        private var fetchingView: some View {
            Section {} header: {
                Text(
                    !noneFetched ?
                        "\nConfirm the fetched settings before saving" : "No fetched setting"
                )
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .textCase(nil)
                .font(.previewHeadline)
            }
        }

        private var listFetchedView: some View {
            Group {
                if let profiles = profiles {
                    if let defaultProfiles = profiles.store["default"] {
                        // Basals
                        let basals_ = defaultProfiles.basal.map({
                            basal in
                            BasalProfileEntry(
                                start: basal.time + ":00",
                                minutes: offset(basal.time) / 60,
                                rate: basal.value
                            )
                        })

                        let units: String = freeapsSettings?.units.rawValue ?? GlucoseUnits.mmolL.rawValue

                        Section {
                            ForEach(basals_, id: \.start) { item in
                                HStack {
                                    Text(item.start)
                                    Spacer()
                                    Text(item.rate.formatted())
                                    Text("U/h")
                                }
                            }
                        } header: { Text("Basals") }

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
                        } header: { Text("Insulin Sensitivities") }

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

                // Pump Settings
                if let pumpSettings = pumpSettings {
                    Section {
                        HStack {
                            Text("Max Bolus")
                            Spacer()
                            Text(pumpSettings.maxBolus.formatted())
                            Text("U")
                        }
                        HStack {
                            Text("Max Basal")
                            Spacer()
                            Text(pumpSettings.maxBasal.formatted())
                            Text("U")
                        }
                        HStack {
                            Text("DIA")
                            Spacer()
                            Text(pumpSettings.insulinActionCurve.formatted())
                            Text("h")
                        }
                    } header: { Text("Pump Settings") }
                }

                // Temp Targets
                if let tt = tempTargets {
                    let convert: Decimal = (freeapsSettings?.units ?? GlucoseUnits.mmolL) == GlucoseUnits.mmolL ? 0.0555 : 1
                    Section {
                        ForEach(tt, id: \.id) { target in
                            HStack {
                                Text(target.name ?? "")
                                Spacer()
                                Text("\(target.duration) min")
                                Spacer()
                                Text(GlucoseFormatter.string(from: (target.targetBottom ?? 10) * convert as NSNumber) ?? "")
                                Text(freeapsSettings?.units.rawValue ?? GlucoseUnits.mmolL.rawValue)
                            }
                        }
                    } header: { Text("Temp Targets") }
                }

                // iAPS Settings
                if let freeapsSettings = freeapsSettings {
                    Section {
                        Text(trim(freeapsSettings.rawJSON.debugDescription)).font(.settingsListed)
                    } header: { Text("iAPS Settings") }
                }

                // OpenAPS Settings
                if let settings = settings {
                    Section {
                        Text(trim(settings.rawJSON.debugDescription)).font(.settingsListed)
                    } header: { Text("OpenAPS Settings") }
                }

                // Save
                Button {
                    save()
                    viewInt += 1
                }
                label: { Text("Save settings") }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color(.systemBlue))
                    .tint(.white)
            }
        }

        private var importedView: some View {
            Group {
                Section {
                    if int == 2 {
                        HStack {
                            Text("Profile")
                            Spacer()
                            Text(profile)
                        }.foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Basals")
                        Spacer()
                        Text(basalsOK ? "OK" : "No")
                            .foregroundStyle(basalsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Carb Ratios")
                        Spacer()
                        Text(crsOK ? "OK" : "No")
                            .foregroundStyle(crsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Insulin Sensitivites")
                        Spacer()
                        Text(isfsOK ? "OK" : "No")
                            .foregroundStyle(isfsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Targets")
                        Spacer()
                        Text(targetsOK ? "OK" : "No")
                            .foregroundStyle(targetsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Pump Settings")
                        Spacer()
                        Text(pumpSettingsOK ? "OK" : "No")
                            .foregroundStyle(pumpSettingsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Temp Targets")
                        Spacer()
                        Text(tempTargetsOK ? "OK" : "No")
                            .foregroundStyle(tempTargetsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Preferences")
                        Spacer()
                        Text(settingsOK ? "OK" : "No")
                            .foregroundStyle(settingsOK ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("iAPS Settings")
                        Spacer()
                        Text(freeapsSettingsOK ? "OK" : "No")
                            .foregroundStyle(freeapsSettingsOK ? Color(.darkGreen) : .red)
                    }
                } header: {
                    Text("Fetched settings").font(.previewNormal)
                }

                if !allDone {
                    Section {
                        Button {
                            importSettings(id: inSitu ? id_ : token)
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                        }
                        label: { Text("Try Again") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color(.systemBlue))
                            .tint(.white)
                    }
                }

                Button {
                    if noneFetched {
                        reset()
                        firstRun = false
                    } else {
                        viewInt += 1
                    }
                }
                label: { Text("Continue") }
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
                        Text(basalsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(basalsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Carb Ratios")
                        Spacer()
                        Text(crsOKSaved ? "Saved" : "Not saved")
                            .foregroundStyle(crsOKSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Insulin Sensitivites")
                        Spacer()
                        Text(isfsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(isfsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Targets")
                        Spacer()
                        Text(targetsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(targetsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Pump Settings")
                        Spacer()
                        Text(pumpSettingsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(pumpSettingsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Temp Targets")
                        Spacer()
                        Text(tempTargetsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(tempTargetsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("Preferences")
                        Spacer()
                        Text(settingsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(settingsSaved ? Color(.darkGreen) : .red)
                    }

                    HStack {
                        Text("iAPS Settings")
                        Spacer()
                        Text(freeapsSettingsSaved ? "Saved" : "Not saved")
                            .foregroundStyle(freeapsSettingsSaved ? Color(.darkGreen) : .red)
                    }
                } header: {
                    Text("Saved settings").font(.previewNormal)
                }

                Button {
                    if int == 2 {
                        close()
                    } else {
                        reset()
                        onboardingDone()
                    }
                }
                label: { Text("OK") }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color(.systemBlue))
                    .tint(.white)
            }
        }

        private func reset() {
            viewInt = 0
        }

        private var allDone: Bool {
            (
                basalsOK && isfsOK && crsOK && freeapsSettingsOK && settingsOK && targetsOK && pumpSettingsOK && tempTargetsOK
            )
        }

        private var noneFetched: Bool {
            (
                !basalsOK && !isfsOK && !crsOK && !freeapsSettingsOK && !settingsOK && !targetsOK && !pumpSettingsOK &&
                    !tempTargetsOK
            )
        }

        private func importSettings(id: String) {
            var profile_ = "default"
            if !profile.isEmpty {
                profile_ = profile
            } else if let name = CoreDataStorage().fetchSettingProfileName() {
                profile_ = name
            }

            fetchPreferences(token: id, name: profile_)
            fetchSettings(token: id, name: profile_)
            fetchProfiles(token: id, name: profile_)
            fetchPumpSettings(token: id, name: profile_)
            fetchTempTargets(token: id, name: profile_)
        }

        private func close() {
            dismiss()
            onboardingDone()
        }

        private func fetchPreferences(token: String, name: String) {
            let database = Database(token: token)
            database.fetchPreferences(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Preferences fetched from database")
                        self.settingsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                    }
                }
            receiveValue: { self.settings = $0
            }
            .store(in: &lifetime)
        }

        private func fetchSettings(token: String, name: String) {
            let database = Database(token: token)
            database.fetchSettings(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Settings fetched from database")
                        self.freeapsSettingsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                    }
                }
            receiveValue: {
                self.freeapsSettings = $0
            }
            .store(in: &lifetime)
        }

        private func fetchProfiles(token: String, name: String) {
            let database = Database(token: token)
            database.fetchProfile(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Profiles fetched from database")
                        self.basalsOK = true
                        self.isfsOK = true
                        self.crsOK = true
                        self.targetsOK = true
                        self.diaOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        print("Profiles: No")
                    }
                }
            receiveValue: { self.profiles = $0
            }
            .store(in: &lifetime)
        }

        private func fetchPumpSettings(token: String, name: String) {
            let database = Database(token: token)
            database.fetchPumpSettings(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Pump Settings fetched from database")
                        self.pumpSettingsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                    }
                }
            receiveValue: {
                self.pumpSettings = $0
            }
            .store(in: &lifetime)
        }

        private func fetchTempTargets(token: String, name: String) {
            let database = Database(token: token)
            database.fetchTempTargets(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Temp Targets fetched from database")
                        self.tempTargetsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                    }
                }
            receiveValue: {
                self.tempTargets = $0.tempTargets
            }
            .store(in: &lifetime)
        }

        private func verifyProfiles() {
            if let fetchedProfiles = profiles {
                if let defaultProfiles = fetchedProfiles.store["default"] {
                    // Basals
                    let basals_ = defaultProfiles.basal.map({
                        basal in
                        BasalProfileEntry(
                            start: basal.time + ":00",
                            minutes: self.offset(basal.time) / 60,
                            rate: basal.value
                        )
                    })
                    let syncValues = basals_.map {
                        RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
                    }

                    if let apsManager = state.apsM(resolver: resolver), let pump = apsManager.pumpManager {
                        pump.syncBasalRateSchedule(items: syncValues) { result in
                            switch result {
                            case .success:
                                self.state.saveFile(basals_, filename: OpenAPS.Settings.basalProfile)
                                debug(.service, "Imported Basals saved to pump!")
                                self.basalsSaved = true
                            case .failure:
                                debug(.service, "Imported Basals couldn't be save to pump")
                            }
                        }
                    } else {
                        state.saveFile(basals_, filename: OpenAPS.Settings.basalProfile)
                        // state.storage.save(basals_, as: OpenAPS.Settings.basalProfile)
                        debug(.service, "Imported Basals have been saved to file storage.")
                        basalsSaved = true
                    }

                    // Glucoce Unit
                    let preferredUnit = GlucoseUnits(rawValue: defaultProfiles.units) ?? .mmolL

                    // ISFs
                    let sensitivities = defaultProfiles.sens.map { sensitivity -> InsulinSensitivityEntry in
                        InsulinSensitivityEntry(
                            sensitivity: sensitivity.value,
                            offset: self.offset(sensitivity.time) / 60,
                            start: sensitivity.time
                        )
                    }

                    let isfs_ = InsulinSensitivities(
                        units: preferredUnit,
                        userPrefferedUnits: preferredUnit,
                        sensitivities: sensitivities
                    )

                    // state.storage.save(isfs_, as: OpenAPS.Settings.insulinSensitivities)
                    state.saveFile(isfs_, filename: OpenAPS.Settings.insulinSensitivities)

                    debug(.service, "Imported ISFs have been saved to file storage.")
                    isfsSaved = true

                    // CRs
                    let carbRatios = defaultProfiles.carbratio.map({
                        cr -> CarbRatioEntry in
                        CarbRatioEntry(
                            start: cr.time,
                            offset: (cr.timeAsSeconds ?? 0) / 60,
                            ratio: cr.value
                        )
                    })
                    let crs_ = CarbRatios(units: CarbUnit.grams, schedule: carbRatios)

                    // state.storage.save(crs_, as: OpenAPS.Settings.carbRatios)
                    state.saveFile(crs_, filename: OpenAPS.Settings.carbRatios)
                    debug(.service, "Imported CRs have been saved to file storage.")
                    crsOKSaved = true

                    // Targets
                    let glucoseTargets = defaultProfiles.target_low.map({
                        target -> BGTargetEntry in
                        BGTargetEntry(
                            low: target.value,
                            high: target.value,
                            start: target.time,
                            offset: (target.timeAsSeconds ?? 0) / 60
                        )
                    })
                    let targets_ = BGTargets(units: preferredUnit, userPrefferedUnits: preferredUnit, targets: glucoseTargets)

                    // state.storage.save(targets_, as: OpenAPS.Settings.bgTargets)
                    state.saveFile(targets_, filename: OpenAPS.Settings.bgTargets)
                    debug(.service, "Imported Targets have been saved to file storage.")
                    targetsSaved = true
                }
            }
        }

        private func verifySettings() {
            if let fetchedSettings = freeapsSettings {
                // state.storage.save(fetchedSettings, as: OpenAPS.FreeAPS.settings)
                state.saveFile(fetchedSettings, filename: OpenAPS.FreeAPS.settings)
                freeapsSettingsSaved = true
                debug(.service, "Imported iAPS Settings have been saved to file storage.")
            }
        }

        private func verifyPreferences() {
            if let fetchedSettings = settings {
                // state.storage.save(fetchedSettings, as: OpenAPS.Settings.preferences)
                state.saveFile(fetchedSettings, filename: OpenAPS.Settings.preferences)
                settingsSaved = true
                debug(.service, "Imported Preferences have been saved to file storage.")
            }
        }

        private func verifyPumpSettings() {
            if let fetchedSettings = pumpSettings {
                // state.storage.save(fetchedSettings, as: OpenAPS.Settings.settings)
                state.saveFile(fetchedSettings, filename: OpenAPS.Settings.settings)
                pumpSettingsSaved = true
                debug(.service, "Imported Pump settings have been saved to file storage.")
            }
        }

        private func verifyTempTargets() {
            if let fetchedTargets = tempTargets {
                // state.storage.save(fetchedTargets, as: OpenAPS.Settings.tempTargets)
                state.saveFile(fetchedTargets, filename: OpenAPS.Settings.tempTargets)
                tempTargetsSaved = true
                debug(.service, "Imported Temp targets have been saved to file storage.")
            }
        }

        private func onboardingDone() {
            CoreDataStorage().saveOnbarding()
            imported = true
        }

        private func offset(_ string: String) -> Int {
            let hours = Int(string.prefix(2)) ?? 0
            let minutes = Int(string.suffix(2)) ?? 0
            return ((hours * 60) + minutes) * 60
        }

        private func save() {
            verifyProfiles()
            verifySettings()
            verifyPreferences()
            verifyPumpSettings()
            verifyTempTargets()
            state.activeProfile(profile)
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
            let data = trim.components(separatedBy: ",").sorted { $0.count < $1.count }
                .debugDescription.replacingOccurrences(of: ", ", with: "\n")
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "\"", with: "")

            return data
        }
    }
}
