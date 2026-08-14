import Foundation
import Swinject

protocol DatabaseManager: Sendable {
    func uploadStatistics(dailystat: Statistics, profile: NightscoutProfileStore?) async
    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async
    func uploadPreviousDayLog() async
    func uploadVersion(version: DatabaseStatisticsVersion) async
    func fetchVersion() async
    func retryPendingLogUpload() async
}

actor BaseDatabaseManager: DatabaseManager, LifetimeOwner, AppService {
    private let storage: FileStorage
    private let database: Database
    private let reachabilityManager: ReachabilityManager
    private let contactTrickManager: ContactTrickManager
    private let appCoordinator: AppCoordinator

    private let coreDataStorage = CoreDataStorage()
    private let overrideStorage: OverrideStorage

    let lifetime = Lifetime()

    // Pending log upload — set when upload fails or network is unavailable at rotation time.
    // Persisted to disk (log_pending.txt + UserDefaults) so the upload survives app restarts.
    // Cleared automatically on successful upload.
    private var pendingLogDate: String?

    private let pendingLogDateKey = "iAPS.pendingLogUploadDate"

    private static let dateFmt = {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.locale = Locale(identifier: "en_US_POSIX")
        return dateFmt
    }()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var isLogUploadEnabled: Bool {
        // Logs are uninterpretable without the settings/profile they ran under,
        // so they only upload when full Backup is also enabled.
        let settings = appCoordinator.settings.value
        return settings.uploadStats && settings.uploadLogs
    }

    init(
        storage: FileStorage,
        database: Database,
        reachabilityManager: ReachabilityManager,
        contactTrickManager: ContactTrickManager,
        appCoordinator: AppCoordinator,
        overrideStorage: OverrideStorage
    ) {
        self.storage = storage
        self.database = database
        self.reachabilityManager = reachabilityManager
        self.contactTrickManager = contactTrickManager
        self.appCoordinator = appCoordinator
        self.overrideStorage = overrideStorage
        pendingLogDate = UserDefaults.standard.string(forKey: pendingLogDateKey)
    }

    // this is called at the app start
    func start() async {
        Foundation.NotificationCenter.default.addObserver(
            forName: .logDidRotate,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let logDate = notification.userInfo?["logDate"] as? Date else { return }
            Task {
                await self?.handleLogRotation(logDate: logDate)
            }
        }
    }

    func fetchVersion() async {
        guard isNetworkReachable else {
            return
        }
        do {
            let version = try await database.fetchVersion()
            debug(.nightscout, "Version fetched from " + IAPSconfig.statURL.absoluteString)
            await coreDataStorage.saveVersion(version)
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    func uploadVersion(version: DatabaseStatisticsVersion) async {
        do {
            try await database.uploadStats(stats: nil, version: version)
            debug(.nightscout, "Version uploaded")
            await coreDataStorage.saveStatUploadCount()
            UserDefaults.standard.set(false, forKey: IAPSconfig.newVersion)
        } catch {
            debug(.nightscout, "Version upload failed: \(error.localizedDescription)")
        }
    }

    func uploadStatistics(dailystat: Statistics, profile: NightscoutProfileStore?) async {
        do {
            let isNewVersion = UserDefaults.standard.bool(forKey: IAPSconfig.newVersion)
            try await database.uploadStats(stats: dailystat, version: nil)
            debug(.nightscout, "Statistics uploaded")
            await coreDataStorage.saveStatUploadCount()
            UserDefaults.standard.set(false, forKey: IAPSconfig.newVersion)
            await uploadProfileAndSettings(profile: profile, force: isNewVersion)
        } catch {
            debug(.nightscout, "Statistics upload failed: \(error.localizedDescription)")
        }
    }

    private var profileName: String {
        get async {
            await coreDataStorage.fetchSettingProfileName()
        }
    }

    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async {
        let settings = appCoordinator.settings.value
        guard settings.uploadStats || force else { return }

        let preferences = appCoordinator.preferences.value
        let pumpSettings = appCoordinator.pumpSettings.value

        let profileName = await self.profileName

        if let profile, let ps = profile.store[profile.defaultProfile] {
            let uploadedProfile = await storage.retrieve(
                OpenAPS.Nightscout.uploadedProfileToDatabase,
                as: DatabaseProfileStore.self
            )
            // upload profiles to database WHEN CHANGED
            if uploadedProfile?.store["default"] != ps || force {
                await uploadProfile(profile)
            } else {
                debug(.nightscout, "NightscoutManager uploadProfile to database, no profile change")
            }
        }

        let tempTargets = await storage.retrieve(OpenAPS.FreeAPS.tempTargetsPresets, as: [TempTarget].self)

        let uploadedPreferences = await storage.retrieve(OpenAPS.Nightscout.uploadedPreferences, as: Preferences.self)
        // UPLOAD PREFERENCES WHEN CHANGED
        if uploadedPreferences != preferences || force {
            let prefs = DatabasePreferences(preferences: preferences, profile: profileName)
            await uploadPreferences(prefs)
        } else {
            debug(.nightscout, "NightscoutManager Preferences, preferences unchanged")
        }

        let uploadedSettings = await storage.retrieve(OpenAPS.Nightscout.uploadedSettings, as: FreeAPSSettings.self)
        // UPLOAD FreeAPS Settings WHEN CHANGED
        if uploadedSettings != settings || force {
            let settings = DatabaseSettings(settings: settings, profile: profileName)
            await uploadSettings(settings)
        } else {
            debug(.nightscout, "NightscoutManager Settings, settings unchanged")
        }

        let uploadedPumpSettings = await storage.retrieve(OpenAPS.Nightscout.uploadedPumpSettings, as: PumpSettings.self)
        // UPLOAD PumpSettings WHEN CHANGED
        if uploadedPumpSettings != pumpSettings || force {
            await uploadPumpSettings(pumpSettings, name: profileName)
        } else {
            debug(.nightscout, "PumpSettings unchanged")
        }

        if let tempTargets {
            let uploadedTempTargets = await storage.retrieve(
                OpenAPS.Nightscout.uploadedTempTargetsDatabase,
                as: [TempTarget].self
            )
            // UPLOAD Temp Targets WHEN CHANGED
            if uploadedTempTargets != tempTargets || force {
                await uploadTempTargets(tempTargets, name: profileName)
            } else {
                debug(.nightscout, "Temp targets unchanged")
            }
        }

        let mealPresets = await mealPresetDatabaseUpload(profile: profileName)
        if !mealPresets.presets.isEmpty {
            let uploadedMealPresets = await storage.retrieve(OpenAPS.Nightscout.uploadedMealPresets, as: DatabaseMeal.self)
            // Upload Meal Presets when needed
            if uploadedMealPresets != mealPresets || force {
                await uploadMealPresets(mealPresets)
            } else {
                debug(.nightscout, "Meal Presets unchanged")
            }
        }

        let overridePresets = await overridePresetDatabaseUpload(profile: profileName)
        if !overridePresets.presets.isEmpty {
            let uploadedOverridePresets = await storage.retrieve(
                OpenAPS.Nightscout.uploadedOverridePresets,
                as: DatabaseOverride.self
            )
            // Upload Override Presets when needed
            if uploadedOverridePresets != overridePresets || force {
                await uploadOverridePresets(overridePresets)
            } else {
                debug(.nightscout, "Override Presets unchanged")
            }
        }

        // Upload Contact Trick (display config) when needed
        let contacts = await contactTrickManager.currentContacts
        let uploadedContacts = await storage.retrieve(
            OpenAPS.Nightscout.uploadedContactTrick,
            as: [ContactTrickEntry].self
        )
        if uploadedContacts != contacts || force {
            await uploadContactTrick(contacts, profile: profileName)
        } else {
            debug(.nightscout, "Contact Trick unchanged")
        }

        // Upload AI settings when needed. Unlike the sections above there's no "is it empty"
        // guard: these are plain UserDefaults values that always read back as something (a
        // provider choice, a toggle), so the unchanged-check is the only thing that needs to
        // suppress a repeat upload.
        let aiSettings = convertAISettings()
        let uploadedAiSettings = await storage.retrieve(
            OpenAPS.Nightscout.uploadedAISettings,
            as: MigratedAISettings.self
        )
        if aiSettings != uploadedAiSettings || force
        {
            await uploadAISettings(aiSettings, profile: profileName)
        } else {
            debug(.nightscout, "AI settings unchanged")
        }
    }

    private func uploadMealPresets(_ presets: DatabaseMeal) async {
        do {
            try await database.uploadMealPresets(presets)
            debug(.nightscout, "Meal presets uploaded to database. Profile: \(presets.profile)")
            await storage.save(presets, as: OpenAPS.Nightscout.uploadedMealPresets)
            await saveToCoreData(presets.profile)
        } catch {
            debug(.nightscout, "Meal presets failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadOverridePresets(_ presets: DatabaseOverride) async {
        do {
            try await database.uploadOverridePresets(presets)
            debug(.nightscout, "Override presets uploaded to database. Profile: \(presets.profile)")
            await storage.save(presets, as: OpenAPS.Nightscout.uploadedOverridePresets)
            await saveToCoreData(presets.profile)
        } catch {
            debug(.nightscout, "Override presets failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadContactTrick(_ contacts: [ContactTrickEntry], profile: String?) async {
        do {
            try await database.uploadContactTrick(contacts: contacts, profile: profile ?? "default")
            debug(.nightscout, "Contact Trick uploaded to database.")
            await self.storage.save(contacts, as: OpenAPS.Nightscout.uploadedContactTrick)
        } catch {
            debug(.nightscout, "Contact Trick failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadAISettings(_ settings: MigratedAISettings, profile: String?) async {
        do {
            try await database.uploadAISettings(settings: settings, profile: profile)
            debug(.nightscout, "AI settings uploaded to database.")
            await self.storage.save(settings, as: OpenAPS.Nightscout.uploadedAISettings)
        } catch {
            debug(.nightscout, "AI settings failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadPreferences(_ preferences: DatabasePreferences) async {
        do {
            try await database.uploadPrefs(preferences)
            debug(.nightscout, "Preferences uploaded to database. Profile: \(preferences.profile ?? "")")
            await storage.save(preferences, as: OpenAPS.Nightscout.uploadedPreferences)
            await saveToCoreData(preferences.profile ?? "default")
        } catch {
            debug(.nightscout, "Preferences failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadProfile(_ profile: NightscoutProfileStore) async {
        do {
            try await database.uploadProfile(profile)
            debug(.nightscout, "Profiles uploaded to database. Profile: \(profile.profile ?? "")")
            await storage.save(profile, as: OpenAPS.Nightscout.uploadedProfileToDatabase)
        } catch {
            debug(.nightscout, "Profiles failed to upload to databse: \(error.localizedDescription)")
        }
    }

    private func uploadSettings(_ settings: DatabaseSettings) async {
        do {
            try await database.uploadSettings(settings)
            debug(.nightscout, "Settings uploaded to database. Profile: \(settings.profile ?? "")")
            await storage.save(settings, as: OpenAPS.Nightscout.uploadedSettings)
            await saveToCoreData(settings.profile ?? "default")
        } catch {
            debug(.nightscout, "Settings failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadPumpSettings(_ settings: PumpSettings, name: String?) async {
        let concentration = await coreDataStorage.insulinConcentration().concentration
        let upload = DatabasePumpSettings(
            settings: settings,
            profile: name,
            insulinConcentration: concentration
        )
        do {
            try await database.uploadPumpSettings(upload)
            debug(.nightscout, "Pump settings uploaded to database. Profile: \(upload.profile ?? "")")
            await storage.save(settings, as: OpenAPS.Nightscout.uploadedPumpSettings)
            await saveToCoreData(name ?? "default")
        } catch {
            debug(.nightscout, "Pump settings failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func uploadTempTargets(_ targets: [TempTarget], name: String?) async {
        let upload = DatabaseTempTargets(tempTargets: targets, profile: name ?? "default")
        do {
            try await database.uploadTempTargets(upload)
            debug(.nightscout, "Temp targets uploaded to database. Profile: \(upload.profile ?? "")")
            await storage.save(targets, as: OpenAPS.Nightscout.uploadedTempTargetsDatabase)
            await saveToCoreData(name ?? "default")
        } catch {
            debug(.nightscout, "Temp targets failed to upload to database: \(error.localizedDescription)")
        }
    }

    private func handleLogRotation(logDate: Date) async {
        guard isLogUploadEnabled else { return }

        let dateString = Self.dateFmt.string(from: logDate)

        guard let logData = try? Data(contentsOf: URL(fileURLWithPath: SimpleLogReporter.logFilePrev)),
              !logData.isEmpty
        else {
            debug(.nightscout, "Log upload skipped — log_prev.txt missing or empty")
            return
        }

        guard isNetworkReachable else {
            debug(.nightscout, "Log upload queued for \(dateString) — no network at rotation time")
            savePendingUpload(date: dateString, data: logData)
            return
        }

        await performLogUpload(logData: logData, dateString: dateString)
    }

    func retryPendingLogUpload() async {
        guard isLogUploadEnabled,
              let pendingLogDate = pendingLogDate,
              isNetworkReachable else { return }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: SimpleLogReporter.logFilePending)),
              !data.isEmpty
        else {
            // No valid pending file — remove any orphaned UserDefaults key
            clearPendingUpload()
            return
        }

        debug(.nightscout, "Retrying log upload for \(pendingLogDate)")
        await performLogUpload(logData: data, dateString: pendingLogDate)
    }

    func uploadPreviousDayLog() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let dateString = Self.dateFmt.string(from: yesterday)

        guard let logData = try? Data(contentsOf: URL(fileURLWithPath: SimpleLogReporter.logFilePrev)),
              !logData.isEmpty
        else {
            debug(.nightscout, "Manual log upload skipped — log_prev.txt missing or empty")
            return
        }

        do {
            try await database.uploadLog(logData, logDate: dateString)
            debug(.nightscout, "Manual log upload succeeded for \(dateString)")
        } catch {
            debug(.nightscout, "Manual log upload failed: \(error.localizedDescription)")
        }
    }

    private func performLogUpload(logData: Data, dateString: String) async {
        do {
            try await database.uploadLog(logData, logDate: dateString)
            debug(.nightscout, "Log upload succeeded for \(dateString)")
            clearPendingUpload()
        } catch {
            debug(
                .nightscout,
                "Log upload failed for \(dateString) (will retry later): \(error.localizedDescription)"
            )
            savePendingUpload(date: dateString, data: logData)
        }
    }

    // ── Pending-upload persistence ────────────────────────────────────────────

    /// Writes the failed log to disk and records its date in UserDefaults so the
    /// upload can be resumed after the app is killed and relaunched.
    private func savePendingUpload(date: String, data: Data) {
        try? data.write(to: URL(fileURLWithPath: SimpleLogReporter.logFilePending))
        UserDefaults.standard.set(date, forKey: pendingLogDateKey)
        pendingLogDate = date
    }

    /// Removes the pending log file and UserDefaults entry after a successful upload.
    private func clearPendingUpload() {
        try? FileManager.default.removeItem(atPath: SimpleLogReporter.logFilePending)
        UserDefaults.standard.removeObject(forKey: pendingLogDateKey)
        pendingLogDate = nil
    }

    private func overridePresetDatabaseUpload(profile: String) async -> DatabaseOverride {
        DatabaseOverride(profile: profile, presets: await convertOverridePresets())
    }

    private func mealPresetDatabaseUpload(profile: String) async -> DatabaseMeal {
        let presets = await convertMealPresets()
        return DatabaseMeal(profile: profile, presets: presets)
    }

    private func convertMealPresets() async -> [MigratedMeals] {
        let meals = await coreDataStorage.fetchMealPresets()
        return meals.map({ item -> MigratedMeals in
            MigratedMeals(
                carbs: item.carbs ?? 0,
                dish: item.dish ?? "",
                fat: item.fat ?? 0,
                protein: item.protein ?? 0,
                fiber: item.fiber,
                sugars: item.sugars,
                glycemicIndex: item.glycemicIndex,
                portionSize: item.portionSize,
                per100: item.per100,
                mealUnits: item.mealUnits,
                standardName: item.standardName,
                standardServing: item.standardServing,
                standardServingSize: item.standardServingSize,
                imageURL: item.imageURL,
                tags: item.tags,
                foodID: item.foodID?.uuidString,
                // Read the stored entries directly rather than via micronutrientValuesTyped(),
                // which rescales by portion and drops substances it doesn't recognise — fine for
                // display, lossy for a backup.
                micronutrients: (item.micronutrient ?? []).compactMap { entry -> MigratedMicronutrient? in
                    guard let name = entry.micronutrient.name else { return nil }
                    return MigratedMicronutrient(
                        name: name,
                        type: entry.micronutrient.type,
                        unit: entry.micronutrient.unit,
                        amount: entry.amount,
                        per100: entry.per100
                    )
                }
            )
        })
    }

    private func convertOverridePresets() async -> [MigratedOverridePresets] {
        let presets = await overrideStorage.fetchOverridePresets()
        return presets.map { item -> MigratedOverridePresets in
            // The Auto ISF block lives in its own entity keyed by the preset's id, so it has to be
            // looked up per preset rather than read off the preset itself.
            let autoISF = item.aisf.map { MigratedAutoISF($0) }

            return MigratedOverridePresets(
                advancedSettings: item.advancedSettings,
                cr: item.cr,
                date: item.date ?? Date(),
                duration: item.duration ?? 0,
                emoji: item.emoji ?? "",
                end: item.end ?? 0,
                id: item.id,
                indefininite: item.indefinite,
                isf: item.isf,
                isndAndCr: item.isfAndCr, basal: item.basal,
                maxIOB: item.maxIOB ?? 0,
                name: item.name ?? "",
                overrideMaxIOB: item.overrideMaxIOB,
                percentage: item.percentage,
                smbAlwaysOff: item.smbIsAlwaysOff,
                smbIsOff: item.smbIsOff,
                smbMinutes: item.smbMinutes ?? 0,
                start: item.start ?? 0,
                target: item.target ?? 0,
                uamMinutes: item.uamMinutes ?? 0,
                autoISF: autoISF
            )
        }
    }

    /// Snapshot the AI settings out of UserDefaults. The provider API keys are intentionally not
    /// read here — see `MigratedAISettings`.
    private func convertAISettings() -> MigratedAISettings {
        let d = UserDefaults.standard
        return MigratedAISettings(
            textSearchProvider: d.textSearchProvider.rawValue,
            barcodeSearchProvider: d.barcodeSearchProvider.rawValue,
            aiImageProvider: d.aiImageProvider.rawValue,
            aiTextProvider: d.aiTextProvider.rawValue,
            preferredLanguage: d.userPreferredLanguageForAI,
            preferredRegion: d.userPreferredRegionForAI,
            nutritionAuthority: d.userPreferredNutritionAuthorityForAI.rawValue,
            sendSmallerImages: d.shouldSendSmallerImagesToAI,
            aiTextSearchByDefault: d.aiTextSearchByDefault,
            aiAddImageCommentByDefault: d.aiAddImageCommentByDefault,
            aiSavePhotosToLibrary: d.aiSavePhotosToLibrary,
            aiProgressAnimation: d.aiProgressAnimation
        )
    }

    private func saveToCoreData(_ name: String) async {
        await coreDataStorage.profileSettingUploaded(name: name)
    }
}
