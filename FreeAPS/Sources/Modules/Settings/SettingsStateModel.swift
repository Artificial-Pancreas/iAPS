import Combine
import LoopKit
import SwiftUI

extension Settings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var fileManager: FileManager!
        @Injected() private var nightscoutManager: NightscoutManager!
        @Injected() private var storage: FileStorage!
        @Injected() private var apsManager: APSManager!

        @Published var closedLoop = false
        @Published var debugOptions = false
        @Published var animatedBackground = false
        @Published var disableCGMError = true
        @Published var firstRun: Bool = true
        @Published var imported: Bool = false
        @Published var token: String = ""

        @Published var basals: [BasalProfileEntry]?
        @Published var basalsOK: Bool = false
        @Published var basalsSaved: Bool = false

        @Published var crs: [CarbRatioEntry]?
        @Published var crsOK: Bool = false
        @Published var crsOKSaved: Bool = false

        @Published var isfs: [InsulinSensitivityEntry]?
        @Published var isfsOK: Bool = false
        @Published var isfsSaved: Bool = false

        @Published var settings: Preferences?
        @Published var settingsOK: Bool = false
        @Published var settingsSaved: Bool = false

        @Published var freeapsSettings: FreeAPSSettings?
        @Published var freeapsSettingsOK: Bool = false
        @Published var freeapsSettingsSaved: Bool = false

        @Published var profiles: DatabaseProfileStore?
        @Published var profilesOK: Bool = false

        @Published var targets: BGTargetEntry?
        @Published var targetsOK: Bool = false
        @Published var targetsSaved: Bool = false

        private(set) var buildNumber = ""
        private(set) var versionNumber = ""
        private(set) var branch = ""
        private(set) var copyrightNotice = ""

        override func subscribe() {
            nightscoutManager.fetchVersion()

            firstRun = CoreDataStorage().fetchOnbarding()

            subscribeSetting(\.debugOptions, on: $debugOptions) { debugOptions = $0 }
            subscribeSetting(\.closedLoop, on: $closedLoop) { closedLoop = $0 }
            subscribeSetting(\.disableCGMError, on: $disableCGMError) { disableCGMError = $0 }

            broadcaster.register(SettingsObserver.self, observer: self)

            buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

            versionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

            // Read branch information from the branch.txt instead of infoDictionary
            if let branchFileURL = Bundle.main.url(forResource: "branch", withExtension: "txt"),
               let branchFileContent = try? String(contentsOf: branchFileURL)
            {
                let lines = branchFileContent.components(separatedBy: .newlines)
                for line in lines {
                    let components = line.components(separatedBy: "=")
                    if components.count == 2 {
                        let key = components[0].trimmingCharacters(in: .whitespaces)
                        let value = components[1].trimmingCharacters(in: .whitespaces)

                        if key == "BRANCH" {
                            branch = value
                            break
                        }
                    }
                }
            } else {
                branch = "Unknown"
            }

            copyrightNotice = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""

            subscribeSetting(\.animatedBackground, on: $animatedBackground) { animatedBackground = $0 }
        }

        func logItems() -> [URL] {
            var items: [URL] = []

            if fileManager.fileExists(atPath: SimpleLogReporter.logFile) {
                items.append(URL(fileURLWithPath: SimpleLogReporter.logFile))
            }

            if fileManager.fileExists(atPath: SimpleLogReporter.logFilePrev) {
                items.append(URL(fileURLWithPath: SimpleLogReporter.logFilePrev))
            }

            return items
        }

        func uploadProfileAndSettings(_ force: Bool) {
            NSLog("SettingsState Upload Profile and Settings")
            nightscoutManager.uploadProfileAndSettings(force)
        }

        func hideSettingsModal() {
            hideModal()
        }

        func deleteOverrides() {
            nightscoutManager.deleteAllNSoverrrides() // For testing
        }

        func importSettings(id: String) {
            fetchPreferences(token: id)
            fetchSettings(token: id)
            fetchProfiles(token: id)
        }

        func close() {
            firstRun = false
            token = ""
        }

        func fetchPreferences(token: String) {
            let database = Database(token: token)
            database.fetchPreferences()
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
            receiveValue: { self.settings = $0 }
                .store(in: &lifetime)
        }

        func fetchSettings(token: String) {
            let database = Database(token: token)
            database.fetchSettings()
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

        func fetchProfiles(token: String) {
            let database = Database(token: token)
            database.fetchProfile()
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.service, "Profiles fetched from database")
                        self.basalsOK = true
                        self.isfsOK = true
                        self.crsOK = true
                        self.targetsOK = true
                    case let .failure(error):
                        debug(.service, error.localizedDescription)
                    }
                }
            receiveValue: { self.profiles = $0 }
                .store(in: &lifetime)
        }

        func verifyProfiles() {
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

                    // No pump?
                    if let pump = apsManager.pumpManager {
                        pump.syncBasalRateSchedule(items: syncValues) { result in
                            switch result {
                            case .success:
                                self.storage.save(basals_, as: OpenAPS.Settings.basalProfile)
                                debug(.service, "Imported Basals saved to pump!")
                                self.basalsSaved = true
                            case .failure:
                                debug(.service, "Imported Basals couldn't be save to pump")
                            }
                        }
                    } else {
                        storage.save(basals_, as: OpenAPS.Settings.basalProfile)
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

                    storage.save(isfs_, as: OpenAPS.Settings.insulinSensitivities)
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

                    storage.save(crs_, as: OpenAPS.Settings.carbRatios)
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

                    storage.save(targets_, as: OpenAPS.Settings.bgTargets)
                    debug(.service, "Imported Targets have been saved to file storage.")
                    targetsSaved = true
                }
            }
        }

        func verifySettings() {
            if let fetchedSettings = freeapsSettings {
                storage.save(fetchedSettings, as: OpenAPS.FreeAPS.settings)
                freeapsSettingsSaved = true
                debug(.service, "iAPS Settings have been saved to file storage.")
            }
        }

        func verifyPreferences() {
            if let fetchedSettings = settings {
                storage.save(fetchedSettings, as: OpenAPS.Settings.preferences)
                settingsSaved = true
                debug(.service, "Preferences have been saved to file storage.")
            }
        }

        func onboardingDone() {
            CoreDataStorage().saveOnbarding()
            imported = true
        }

        func offset(_ string: String) -> Int {
            let hours = Int(string.prefix(2)) ?? 0
            let minutes = Int(string.suffix(2)) ?? 0
            return ((hours * 60) + minutes) * 60
        }

        func save() {
            verifyProfiles()
            verifySettings()
            verifyPreferences()
            onboardingDone()
        }
    }
}

extension Settings.StateModel: SettingsObserver {
    func settingsDidChange(_ settings: FreeAPSSettings) {
        closedLoop = settings.closedLoop
        debugOptions = settings.debugOptions
        disableCGMError = settings.disableCGMError
    }
}
