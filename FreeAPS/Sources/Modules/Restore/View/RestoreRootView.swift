import SwiftUI
import Swinject

extension Restore {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        let int: Int
        let profile: String
        let inSitu: Bool
        let id_: String
        var uniqueID: String
        var openAPS: Preferences?

        @Environment(\.dismiss) private var dismiss

        @FetchRequest(
            entity: Presets.entity(), sortDescriptors: []
        ) var savedMeals: FetchedResults<Presets>

        @FetchRequest(
            entity: OverridePresets.entity(), sortDescriptors: []
        ) var overrides: FetchedResults<OverridePresets>

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

        @State var mealPresets: [MigratedMeals]?
        @State var mealPresetsOK: Bool = false
        @State var mealPresetsSaved: Bool = false

        @State var overridePresets: [MigratedOverridePresets]?
        @State var overridePresetsOK: Bool = false
        @State var overridePresetsSaved: Bool = false

        @State var diaOK: Bool = false
        @State var diaSaved: Bool = false

        @State var profileList: String?

        @State var page = 0
        @State var token: String = ""
        @State var lifetime = Lifetime()

        @State var errorString = ""

        var fetchedVersionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        var GlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        var body: some View {
            Form {
                if page == -1 {
                    importResetSettingsView
                } else if page == 0 {
                    onboarding
                } else if page == 1 {
                    tokenView
                    if token != "" {
                        startImportView
                    }
                } else if page == 2 {
                    importedView
                } else if page == 3 {
                    fetchingView
                    listFetchedView
                } else if page == 4 {
                    savedView
                }
            }
            .navigationTitle(!inSitu ? "Onboarding" : "Switch Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                close()
            })
            .navigationBarItems(leading: (page > 0 && !inSitu) ? Button("Back") { page -= 1 } : nil)
            .onAppear {
                page = int
                if inSitu, int != -1 {
                    importSettings(id: id_)
                }
            }
        }

        private var importResetSettingsView: some View {
            Section {
                HStack {
                    Button {
                        importOpenAPSOnly()
                        page = 2
                    }
                    label: { Text("Yes") }
                        .buttonStyle(.borderless)
                        .padding(.leading, 10)

                    Spacer()

                    Button {
                        close()
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

                    Text(
                        "In this new version your OpenAPS settings have been reset to default settings, due to a resolved Type error issue.\n\nFortunately you have a backup of your old OpenAPS settings in the cloud.\n\nDo you want to try to restore these settings now?\n"
                    )
                    .font(.previewNormal)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .textCase(nil)
                .foregroundStyle(.primary)
            }
        }

        private var onboarding: some View {
            Section {
                HStack {
                    Button { page += 1 }
                    label: { Text("Yes") }
                        .buttonStyle(.borderless)
                        .padding(.leading, 10)

                    Spacer()

                    Button {
                        close()
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
                    page += 1
                }
                label: {
                    Text("Start import").frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(!(token == "") ? Color(.systemBlue) : Color(.systemGray4))
                .tint(.white)
            }
        }

        private func migrateProfiles() {
            if !inSitu, (state.fetchSettingProfileNames()?.first?.name ?? "EMPTY_XXX") == "EMPTY_XXX" {
                state.activeProfile("default")
                changeToken(restoreToken: token)
            }
        }

        private func importPresets() {
            if state.coreData.fetchMealPresets().isEmpty {}

            if state.overrrides.fetchProfiles().isEmpty {}
        }

        private var fetchingView: some View {
            Section {} header: {
                Text(
                    !noneFetched ?
                        "\nConfirm the fetched settings before saving" : "No fetched settings"
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
                if let tt = tempTargets, tt.isNotEmpty {
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

                if let mealPresets = mealPresets, displayCoreData {
                    // Meal Presets. CoreData
                    Section {
                        ForEach(mealPresets, id: \.dish) { preset in
                            VStack {
                                Text(preset.dish).foregroundStyle(.secondary)
                                if preset.carbs > 0 {
                                    HStack {
                                        Text("Carbs")
                                        Spacer()
                                        Text("\(preset.carbs) g")
                                    }
                                }
                                if preset.fat > 0 {
                                    HStack {
                                        Text("Fat")
                                        Spacer()
                                        Text("\(preset.fat) g")
                                    }
                                }
                                if preset.protein > 0 {
                                    HStack {
                                        Text("Protein ")
                                        Spacer()
                                        Text("\(preset.protein) g")
                                    }
                                }
                            }
                        }
                    } header: { Text("CoreData Meal Presets") }
                }

                if let overridePresets = overridePresets, displayCoreData {
                    // Override Presets. CoreData
                    Section {
                        ForEach(overridePresets, id: \.id) { preset in
                            HStack {
                                Text(preset.name)
                            }
                        }
                    } header: { Text("CoreData Override Presets") }
                }

                // OpenAPS Settings
                if let settings = settings {
                    Section {
                        Text(trim(settings.rawJSON.debugDescription)).font(.settingsListed)
                    } header: { Text("OpenAPS Settings") }
                }

                // iAPS Settings
                if let freeapsSettings = freeapsSettings {
                    Section {
                        Text(trim(freeapsSettings.rawJSON.debugDescription)).font(.settingsListed)
                    } header: { Text("iAPS Settings") }
                }

                Button {
                    save()
                    page += 1
                    migrateProfiles()
                }
                label: { Text(inSitu ? "Confirm" : "Save settings") }
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

                    if basalsOK {
                        HStack {
                            Text("Basals")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if crsOK {
                        HStack {
                            Text("Carb Ratios")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if isfsOK {
                        HStack {
                            Text("Insulin Sensitivites")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if targetsOK {
                        HStack {
                            Text("Targets")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if pumpSettingsOK {
                        HStack {
                            Text("Pump Settings")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if tempTargetsOK {
                        HStack {
                            Text("Temp Targets")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if settingsOK {
                        HStack {
                            Text("Preferences")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if freeapsSettingsOK {
                        HStack {
                            Text("iAPS Settings")
                            Spacer()
                            Text("OK")
                                .foregroundStyle(Color(.darkGreen))
                        }
                    }

                    if displayCoreData {
                        if mealPresetsOK {
                            HStack {
                                Text("Meal Presets")
                                Spacer()
                                Text("OK")
                                    .foregroundStyle(Color(.darkGreen))
                            }
                        }

                        if overridePresetsOK {
                            HStack {
                                Text("Override Presets")
                                Spacer()
                                Text("OK")
                                    .foregroundStyle(Color(.darkGreen))
                            }
                        }
                    }

                } header: {
                    Text(!allDone ? "Fetching settings..." : "Settings fetched").font(.previewNormal)
                }

                footer: {
                    !allDone ? Text("Fetching can take up to a few seconds") : nil
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
                    } footer: { errorString.isNotEmpty ? Text(errorString).textCase(nil).foregroundStyle(.orange) : nil }
                }

                Button {
                    if noneFetched {
                        close()
                    } else {
                        page += 1
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
                    if basalsOK {
                        HStack {
                            Text("Basals")
                            Spacer()
                            Text(basalsSaved ? "Saved" : "No")
                                .foregroundStyle(basalsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if crsOK {
                        HStack {
                            Text("Carb Ratios")
                            Spacer()
                            Text(crsOKSaved ? "Saved" : "No")
                                .foregroundStyle(crsOKSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if isfsOK {
                        HStack {
                            Text("Insulin Sensitivites")
                            Spacer()
                            Text(isfsSaved ? "Saved" : "No")
                                .foregroundStyle(isfsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if targetsOK {
                        HStack {
                            Text("Targets")
                            Spacer()
                            Text(targetsSaved ? "Saved" : "No")
                                .foregroundStyle(targetsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if pumpSettingsOK {
                        HStack {
                            Text("Pump Settings")
                            Spacer()
                            Text(pumpSettingsSaved ? "Saved" : "No")
                                .foregroundStyle(pumpSettingsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if tempTargetsOK {
                        HStack {
                            Text("Temp Targets")
                            Spacer()
                            Text(tempTargetsSaved ? "Saved" : "No")
                                .foregroundStyle(tempTargetsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if settingsOK {
                        HStack {
                            Text("Preferences")
                            Spacer()
                            Text(settingsSaved ? "Saved" : "No")
                                .foregroundStyle(settingsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if freeapsSettingsOK {
                        HStack {
                            Text("iAPS Settings")
                            Spacer()
                            Text(freeapsSettingsSaved ? "Saved" : "No")
                                .foregroundStyle(freeapsSettingsSaved ? Color(.darkGreen) : .red)
                        }
                    }

                    if displayCoreData {
                        if mealPresetsOK {
                            HStack {
                                Text("Meal Presets")
                                Spacer()
                                Text(mealPresetsSaved ? "Saved" : "No")
                                    .foregroundStyle(mealPresetsSaved ? Color(.darkGreen) : .red)
                            }
                        }

                        if overridePresetsOK {
                            HStack {
                                Text("Override Presets")
                                Spacer()
                                Text(overridePresetsSaved ? "Saved" : "No")
                                    .foregroundStyle(overridePresetsSaved ? Color(.darkGreen) : .red)
                            }
                        }
                    }

                } header: {
                    Text(!allSaved ? "Saving settings..." : "Settings saved").font(.previewNormal)
                }

                Button { close() }
                label: { Text("OK") }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color(.systemBlue))
                    .tint(.white)
            }
        }

        private var allDone: Bool {
            (
                basalsOK && isfsOK && crsOK && freeapsSettingsOK && settingsOK && targetsOK && pumpSettingsOK && tempTargetsOK &&
                    mealPresetsOK && overridePresetsOK
            ) ||
                (
                    inSitu && basalsOK && isfsOK && crsOK && freeapsSettingsOK && settingsOK && targetsOK && pumpSettingsOK &&
                        tempTargetsOK
                )
                ||
                int == -1 && settingsOK
        }

        private var allSaved: Bool {
            settingsSaved && int == -1
        }

        private var noneFetched: Bool {
            !basalsOK && !isfsOK && !crsOK && !freeapsSettingsOK && !settingsOK && !targetsOK && !pumpSettingsOK &&
                !tempTargetsOK && !mealPresetsOK && !overridePresetsOK
        }

        private func importSettings(id: String) {
            var profile_ = "default"
            if inSitu {
                profile_ = profile
            } else if profile_ == "default" {
                // To not overwrite any eventual other current profile with the default settings when force onbarding (or testing)
                state.activeProfile("default")
            }

            fetchProfiles(token: id, name: profile_)
            fetchSettings(token: id, name: profile_)
            fetchPreferences(token: id, name: profile_)
            fetchPumpSettings(token: id, name: profile_)
            fetchTempTargets(token: id, name: profile_)
            // CoreData
            fetchMealPresets(token: id, name: profile_)
            fetchOverridePresets(token: id, name: profile_)
        }

        private func importOpenAPSOnly() {
            settings = openAPS
            settingsOK = true
        }

        private func addError(_ error: String) {
            if errorString.isEmpty {
                errorString += error
            }
        }

        private func close() {
            onboardingDone()
            if inSitu {
                dismiss()
            }
        }

        private var displayCoreData: Bool {
            !inSitu
        }

        private func fetchProfiles() {
            guard let profiles = profileList else { return }
            let string = profiles.components(separatedBy: ",")
            for item in string {
                CoreDataStorage().migrateProfileSettingName(name: item)
            }
        }

        func changeToken(restoreToken: String) {
            let newToken = state.getIdentifier()
            if newToken != restoreToken {
                let database = Database(token: newToken)
                database.moveProfiles(token: newToken, restoreToken: restoreToken)
                    .sink { completion in
                        switch completion {
                        case .finished:
                            debug(.service, "List of profiles moved to a new token")
                            self.retrieveProfiles(restoreToken: newToken)
                            self.fetchProfiles()
                        case let .failure(error):
                            debug(.service, "Failed moving profiles to a new token " + error.localizedDescription)
                            addError(error.localizedDescription)
                        }
                    }
                receiveValue: {}
                    .store(in: &lifetime)
            }
        }

        func retrieveProfiles(restoreToken: String) {
            let database = Database(token: restoreToken)
            let coreData = CoreDataStorage()

            database.fetchProfiles()
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "List of profiles fetched from database")
                        self.fetchProfiles()
                        if !coreData.checkIfActiveProfile() {
                            coreData.activeProfile(name: "default")
                            debug(.service, "default is current profile")
                        }
                    case let .failure(error):
                        debug(.service, "Failed fetching List of profiles from database " + error.localizedDescription)
                        addError(error.localizedDescription)
                    }
                }
            receiveValue: { self.profileList = $0.profiles }
                .store(in: &lifetime)
        }

        private func fetchPreferences(token: String, name: String) {
            let database = Database(token: token)
            database.fetchPreferences(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Preferences fetched from database. Profile: \(name)")
                        self.settingsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        addError("Preferences: " + error.localizedDescription)
                    }
                }
            receiveValue: { self.settings = $0 }
                .store(in: &lifetime)
        }

        private func fetchSettings(token: String, name: String) {
            let database = Database(token: token)
            database.fetchSettings(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Settings fetched from database. Profile: \(name)")
                        self.freeapsSettingsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        addError("iAPS Settings: " + error.localizedDescription)
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
                        debug(.service, "Profiles fetched from database. Profile: \(name)")
                        self.basalsOK = true
                        self.isfsOK = true
                        self.crsOK = true
                        self.targetsOK = true
                        self.diaOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        errorString += error.localizedDescription
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
                        debug(.service, "Pump Settings fetched from database. Profile: \(name)")
                        self.pumpSettingsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        addError("Pump Settings: " + error.localizedDescription)
                    }
                }
            receiveValue: { self.pumpSettings = $0 }
                .store(in: &lifetime)
        }

        private func fetchTempTargets(token: String, name: String) {
            let database = Database(token: token)
            database.fetchTempTargets(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Temp Targets fetched from database. Profile: \(name)")
                        self.tempTargetsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        addError("Temp Targets: " + error.localizedDescription)
                    }
                }
            receiveValue: {
                self.tempTargets = $0.tempTargets
            }
            .store(in: &lifetime)
        }

        private func fetchMealPresets(token: String, name: String) {
            let database = Database(token: token)
            database.fetchMealPressets(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Meal Presets fetched from database. Profile: \(name)")
                        self.mealPresetsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        addError(error.localizedDescription)
                    }
                }
            receiveValue: {
                self.mealPresets = $0.presets
            }
            .store(in: &lifetime)
        }

        private func fetchOverridePresets(token: String, name: String) {
            let database = Database(token: token)
            database.fetchOverridePressets(name)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Override Presets fetched from database. Profile: \(name)")
                        self.overridePresetsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                        addError(error.localizedDescription)
                    }
                }
            receiveValue: {
                self.overridePresets = $0.presets
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

                    state.saveFile(basals_, filename: OpenAPS.Settings.basalProfile)
                    debug(.service, "Imported Basals have been saved to file storage, profile: \(fetchedProfiles.profile ?? "").")
                    basalsSaved = true

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

                    state.saveFile(isfs_, filename: OpenAPS.Settings.insulinSensitivities)

                    debug(.service, "Imported ISFs have been saved to file storage, profile: \(fetchedProfiles.profile ?? "").")
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

                    state.saveFile(crs_, filename: OpenAPS.Settings.carbRatios)
                    debug(.service, "Imported CRs have been saved to file storage, profile: \(fetchedProfiles.profile ?? "").")
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

                    state.saveFile(targets_, filename: OpenAPS.Settings.bgTargets)
                    debug(
                        .service,
                        "Imported Targets have been saved to file storage, profile: \(fetchedProfiles.profile ?? "")."
                    )
                    targetsSaved = true
                }
            }
        }

        private func verifySettings() {
            if let fetchedSettings = freeapsSettings {
                state.saveFile(fetchedSettings, filename: OpenAPS.FreeAPS.settings)
                freeapsSettingsSaved = true
                debug(.service, "Imported iAPS Settings have been saved to file storage, profile: \(profile).")
            }
        }

        private func verifyPreferences() {
            if let fetchedSettings = settings {
                state.saveFile(fetchedSettings, filename: OpenAPS.Settings.preferences)
                settingsSaved = true
                debug(.service, "Imported Preferences have been saved to file storage, profile: \(profile).")
            }
        }

        private func verifyPumpSettings() {
            if let fetchedSettings = pumpSettings {
                state.saveFile(fetchedSettings, filename: OpenAPS.Settings.settings)
                pumpSettingsSaved = true
                debug(.service, "Imported Pump settings have been saved to file storage, profile: \(profile).")
            }
        }

        private func verifyTempTargets() {
            if let fetchedTargets = tempTargets {
                state.saveFile(fetchedTargets, filename: OpenAPS.Settings.tempTargets)
                tempTargetsSaved = true
                debug(.service, "Imported Temp targets have been saved to file storage, profile: \(profile).")
            }
        }

        private func verifyMealPresets() {
            if let mealPresets = mealPresets, !inSitu, savedMeals.isEmpty {
                state.saveMealPresets(mealPresets)
                mealPresetsSaved = true
                debug(.service, "Imported Meal presets have been saved to CoreData, profile: \(profile).")
            }
        }

        private func verifyOverridePresets() {
            if let overridePresets = overridePresets, !inSitu, overrides.isEmpty {
                state.saveOverridePresets(overridePresets)
                overridePresetsSaved = true
                debug(.service, "Imported Override presets have been saved to CoreData, profile: \(profile).")
            }
        }

        private func onboardingDone() {
            CoreDataStorage().saveOnbarding()
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
            verifyMealPresets()
            verifyOverridePresets()
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
