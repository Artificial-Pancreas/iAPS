import Combine
import Foundation
import LoopKitUI
import Swinject
import UIKit

protocol NightscoutManager: GlucoseSource {
    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never>
    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never>
    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never>
    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never>
    func deleteCarbs(_ treatement: DataTable.Treatment, complexMeal: Bool)
    func deleteNormalCarbs(_ treatement: DataTable.Treatment)
    func deleteFPUs(_ treatement: DataTable.Treatment)
    func deleteInsulin(at date: Date)
    func deleteManualGlucose(at: Date)
    func uploadStatus()
    func uploadGlucose()
    func uploadManualGlucose()
    func uploadStatistics(dailystat: Statistics)
    func uploadVersion(json: BareMinimum)
    func uploadPreferences(_ preferences: Preferences)
    func uploadProfileAndSettings(_: Bool)
    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date)
    func deleteAnnouncements()
    func deleteAllNSoverrrides()
    func deleteOverride()
    func editOverride(_ profile: String, _ duration_: Double, _ date: Date)
    var cgmURL: URL? { get }
}

final class BaseNightscoutManager: NightscoutManager, Injectable {
    @Injected() private var keychain: Keychain!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var reachabilityManager: ReachabilityManager!
    @Injected() var healthkitManager: HealthKitManager!

    let overrideStorage = OverrideStorage()

    private let processQueue = DispatchQueue(label: "BaseNetworkManager.processQueue")
    private var ping: TimeInterval?

    private var lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var isUploadEnabled: Bool {
        settingsManager.settings.isUploadEnabled
    }

    private var isUploadGlucoseEnabled: Bool {
        settingsManager.settings.uploadGlucose
    }

    private var nightscoutAPI: NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        broadcaster.register(PumpHistoryObserver.self, observer: self)
        broadcaster.register(CarbsObserver.self, observer: self)
        broadcaster.register(TempTargetsObserver.self, observer: self)
        broadcaster.register(GlucoseObserver.self, observer: self)
        _ = reachabilityManager.startListening(onQueue: processQueue) { status in
            debug(.nightscout, "Network status: \(status)")
        }
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    var cgmURL: URL? {
        if let url = settingsManager.settings.cgm.appURL {
            return url
        }

        let useLocal = settingsManager.settings.useLocalGlucoseSource

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        return maybeNightscout?.url
    }

    func fetchGlucose(since date: Date) -> AnyPublisher<[BloodGlucose], Never> {
        let useLocal = settingsManager.settings.useLocalGlucoseSource
        ping = nil

        if !useLocal {
            guard isNetworkReachable else {
                return Just([]).eraseToAnyPublisher()
            }
        }

        let maybeNightscout = useLocal
            ? NightscoutAPI(url: URL(string: "http://127.0.0.1:\(settingsManager.settings.localGlucosePort)")!)
            : nightscoutAPI

        guard let nightscout = maybeNightscout else {
            return Just([]).eraseToAnyPublisher()
        }

        let startDate = Date()

        return nightscout.fetchLastGlucose(sinceDate: date)
            .tryCatch({ (error) -> AnyPublisher<[BloodGlucose], Error> in
                print(error.localizedDescription)
                return Just([]).setFailureType(to: Error.self).eraseToAnyPublisher()
            })
            .replaceError(with: [])
            .handleEvents(receiveOutput: { value in
                guard value.isNotEmpty else { return }
                self.ping = Date().timeIntervalSince(startDate)
            })
            .eraseToAnyPublisher()
    }

    // MARK: - GlucoseSource

    var glucoseManager: FetchGlucoseManager?
    var cgmManager: CGMManagerUI?
    var cgmType: CGMType = .nightscout

    func fetch(_: DispatchTimer?) -> AnyPublisher<[BloodGlucose], Never> {
        fetchGlucose(since: glucoseStorage.syncDate())
    }

    func fetchIfNeeded() -> AnyPublisher<[BloodGlucose], Never> {
        fetch(nil)
    }

    func fetchCarbs() -> AnyPublisher<[CarbsEntry], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = carbsStorage.syncDate()
        return nightscout.fetchCarbs(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchTempTargets() -> AnyPublisher<[TempTarget], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }

        let since = tempTargetsStorage.syncDate()
        return nightscout.fetchTempTargets(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func fetchAnnouncements() -> AnyPublisher<[Announcement], Never> {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return Just([]).eraseToAnyPublisher()
        }
        let since = announcementsStorage.syncDate()
        return nightscout.fetchAnnouncement(sinceDate: since)
            .replaceError(with: [])
            .eraseToAnyPublisher()
    }

    func deleteCarbs(_ treatement: DataTable.Treatment, complexMeal: Bool) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            carbsStorage.deleteCarbs(at: treatement.id, fpuID: treatement.fpuID ?? "", complex: complexMeal)
            return
        }

        var arg1 = ""
        var arg2 = ""
        if complexMeal {
            arg1 = treatement.id
            arg2 = treatement.fpuID ?? ""
        } else if treatement.isFPU ?? false {
            arg1 = ""
            arg2 = treatement.fpuID ?? ""
        } else {
            arg1 = treatement.id
            arg2 = ""
        }
        healthkitManager.deleteCarbs(syncID: arg1, fpuID: arg2)

        if complexMeal {
            carbsStorage.deleteCarbs(at: treatement.id, fpuID: treatement.fpuID ?? "", complex: true)
        } else if treatement.isFPU ?? false {
            carbsStorage.deleteCarbs(at: "", fpuID: treatement.fpuID ?? "", complex: false)
        } else {
            carbsStorage.deleteCarbs(at: treatement.id, fpuID: "", complex: false)
        }

        if complexMeal {
            // carbsStorage.deleteCarbs(at: treatement.id, fpuID: treatement.fpuID ?? "", complex: true)
            nightscout.deleteCarbs(treatement, _isFPU: false)
                .collect()
                .sink { completion in
                    switch completion {
                    case .finished:
                        let value = !(treatement.isFPU ?? false) ? treatement.id : (treatement.fpuID ?? "")
                        debug(.nightscout, "Carbs with ID \(value) deleted from NS.")
                    case let .failure(error):
                        info(
                            .nightscout,
                            "Deletion of carbs in NightScout not done \n \(error.localizedDescription)",
                            type: MessageType.warning
                        )
                    }
                } receiveValue: { _ in }
                .store(in: &lifetime)

            if (treatement.fpuID ?? "").count > 3 {
                nightscout.deleteCarbs(treatement, _isFPU: true)
                    .collect()
                    .sink { completion in
                        switch completion {
                        case .finished:
                            debug(.nightscout, "Carb equivalents deleted from NS")
                        case let .failure(error):
                            info(
                                .nightscout,
                                "Deletion of carb equivalents in NightScout not done \n \(error.localizedDescription)",
                                type: MessageType.warning
                            )
                        }
                    } receiveValue: { _ in }
                    .store(in: &lifetime)
            }
        } else if treatement.isFPU ?? false {
            // carbsStorage.deleteCarbs(at: "", fpuID: treatement.fpuID ?? "", complex: false)
            nightscout.deleteCarbs(treatement, _isFPU: true)
                .collect()
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Carb equivalents deleted")
                    case let .failure(error):
                        info(
                            .nightscout,
                            "Deletion of carb equivalents in NightScout not done \n \(error.localizedDescription)",
                            type: MessageType.warning
                        )
                    }
                } receiveValue: { _ in }
                .store(in: &lifetime)
        } else {
            // carbsStorage.deleteCarbs(at: treatement.id, fpuID: "", complex: false)
            nightscout.deleteCarbs(treatement, _isFPU: false)
                .collect()
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Carbs with Date \(treatement) deleted from NS.")
                    case let .failure(error):
                        info(
                            .nightscout,
                            "Deletion of carbs in NightScout not done \n \(error.localizedDescription)",
                            type: MessageType.warning
                        )
                    }
                } receiveValue: { _ in }
                .store(in: &lifetime)
        }
    }

    func deleteAnnouncements() {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }
        nightscout.deleteAnnouncements()
            .collect()
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Annuncement(s) deleted from NS.")

                case let .failure(error):
                    info(
                        .nightscout,
                        "Deletion of Announcements not possible \(error.localizedDescription)",
                        type: MessageType.warning
                    )
                }
            } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func deleteNormalCarbs(_ treatement: DataTable.Treatment) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            carbsStorage.deleteCarbs(at: treatement.id, fpuID: "", complex: false)
            return
        }

        carbsStorage.deleteCarbs(at: treatement.id, fpuID: "", complex: false)

        healthkitManager.deleteCarbs(syncID: treatement.id, fpuID: "")

        nightscout.deleteCarbs(treatement, _isFPU: false)
            .collect()
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Carbs with Date \(treatement) deleted from NS.")
                case let .failure(error):
                    info(
                        .nightscout,
                        "Deletion of carbs in NightScout not done \n \(error.localizedDescription)",
                        type: MessageType.warning
                    )
                }
            } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func deleteFPUs(_ treatement: DataTable.Treatment) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            carbsStorage.deleteCarbs(at: "", fpuID: treatement.fpuID ?? "", complex: false)
            return
        }

        healthkitManager.deleteCarbs(syncID: "", fpuID: treatement.fpuID ?? "")

        carbsStorage.deleteCarbs(at: "", fpuID: treatement.fpuID ?? "", complex: false)

        nightscout.deleteCarbs(treatement, _isFPU: true)
            .collect()
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Carb equivalents deleted from NS")
                case let .failure(error):
                    info(
                        .nightscout,
                        "Deletion of carb equivalents in NightScout not done \n \(error.localizedDescription)",
                        type: MessageType.warning
                    )
                }
            } receiveValue: { _ in }
            .store(in: &lifetime)
    }

    func deleteInsulin(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            pumpHistoryStorage.deleteInsulin(at: date)
            return
        }

        nightscout.deleteInsulin(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    self.pumpHistoryStorage.deleteInsulin(at: date)
                    debug(.nightscout, "Insulin deleted from NS")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteManualGlucose(at date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }
        nightscout.deleteManualGlucose(at: date)
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Manual Glucose entry deleted")
                case let .failure(error):
                    debug(.nightscout, error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func uploadStatistics(dailystat: Statistics) {
        let stats = NightscoutStatistics(
            dailystats: dailystat, justVersion: nil
        )

        guard let nightscout = nightscoutAPI else {
            return
        }

        processQueue.async {
            nightscout.uploadStats(stats)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Statistics uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadVersion(json: BareMinimum) {
        let stats = NightscoutStatistics(
            dailystats: nil, justVersion: json
        )

        guard let nightscout = nightscoutAPI else {
            return
        }

        processQueue.async {
            nightscout.uploadStats(stats)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Version uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadPreferences(_ preferences: Preferences) {
        let prefs = NightscoutPreferences(
            preferences: settingsManager.preferences
        )

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadPrefs(prefs)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Preferences uploaded")
                        self.storage.save(preferences, as: OpenAPS.Nightscout.uploadedPreferences)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadSettings(_ settings: FreeAPSSettings) {
        let sets = NightscoutSettings(
            settings: settingsManager.settings
        )

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadSettings(sets)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Settings uploaded")
                        self.storage.save(settings, as: OpenAPS.Nightscout.uploadedSettings)
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadStatus() {
        let iob = storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        var suggested = storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        var enacted = storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)

        if (suggested?.timestamp ?? .distantPast) > (enacted?.timestamp ?? .distantPast) {
            enacted?.predictions = nil
        } else {
            suggested?.predictions = nil
        }

        let loopIsClosed = settingsManager.settings.closedLoop

        var openapsStatus: OpenAPSStatus

        // Only upload suggested in Open Loop Mode. Only upload enacted in Closed Loop Mode.
        if loopIsClosed {
            openapsStatus = OpenAPSStatus(
                iob: iob?.first,
                suggested: nil,
                enacted: enacted,
                version: "0.7.1"
            )
        } else {
            openapsStatus = OpenAPSStatus(
                iob: iob?.first,
                suggested: suggested,
                enacted: nil,
                version: "0.7.1"
            )
        }

        let battery = storage.retrieve(OpenAPS.Monitor.battery, as: Battery.self)

        var reservoir = Decimal(from: storage.retrieveRaw(OpenAPS.Monitor.reservoir) ?? "0")
        if reservoir == 0xDEAD_BEEF {
            reservoir = nil
        }
        let pumpStatus = storage.retrieve(OpenAPS.Monitor.status, as: PumpStatus.self)

        let pump = NSPumpStatus(clock: Date(), battery: battery, reservoir: reservoir, status: pumpStatus)

        let device = UIDevice.current

        let uploader = Uploader(batteryVoltage: nil, battery: Int(device.batteryLevel * 100))

        var status: NightscoutStatus

        status = NightscoutStatus(
            device: NigtscoutTreatment.local,
            openaps: openapsStatus,
            pump: pump,
            uploader: uploader
        )

        storage.save(status, as: OpenAPS.Upload.nsStatus)

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.uploadStatus(status)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Status uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }

        uploadPodAge()
    }

    func uploadPodAge() {
        let uploadedPodAge = storage.retrieve(OpenAPS.Nightscout.uploadedPodAge, as: [NigtscoutTreatment].self) ?? []
        if let podAge = storage.retrieve(OpenAPS.Monitor.podAge, as: Date.self),
           uploadedPodAge.last?.createdAt == nil || podAge != uploadedPodAge.last!.createdAt!
        {
            let siteTreatment = NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsSiteChange,
                createdAt: podAge,
                enteredBy: NigtscoutTreatment.local,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                fat: nil,
                protein: nil,
                targetTop: nil,
                targetBottom: nil
            )
            uploadTreatments([siteTreatment], fileToSave: OpenAPS.Nightscout.uploadedPodAge)
        }
    }

    func uploadProfileAndSettings(_ force: Bool) {
        guard let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading insulinSensitivities")
            return
        }
        guard let settings = storage.retrieve(OpenAPS.FreeAPS.settings, as: FreeAPSSettings.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading settings")
            return
        }
        guard let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading preferences")
            return
        }
        guard let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading bgTargets")
            return
        }
        guard let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading carbRatios")
            return
        }
        guard let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) else {
            debug(.nightscout, "NightscoutManager uploadProfile: error loading basalProfile")
            return
        }

        let sens = sensitivities.sensitivities.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.sensitivity,
                timeAsSeconds: item.offset * 60
            )
        }
        let target_low = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.low,
                timeAsSeconds: item.offset * 60
            )
        }
        let target_high = targets.targets.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.high,
                timeAsSeconds: item.offset * 60
            )
        }
        let cr = carbRatios.schedule.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.ratio,
                timeAsSeconds: item.offset * 60
            )
        }
        let basal = basalProfile.map { item -> NightscoutTimevalue in
            NightscoutTimevalue(
                time: String(item.start.prefix(5)),
                value: item.rate,
                timeAsSeconds: item.minutes * 60
            )
        }

        var nsUnits = ""
        switch settingsManager.settings.units {
        case .mgdL:
            nsUnits = "mg/dl"
        case .mmolL:
            nsUnits = "mmol"
        }

        var carbs_hr: Decimal = 0
        if let isf = sensitivities.sensitivities.map(\.sensitivity).first,
           let cr = carbRatios.schedule.map(\.ratio).first,
           isf > 0, cr > 0
        {
            // CarbImpact -> Carbs/hr = CI [mg/dl/5min] * 12 / ISF [mg/dl/U] * CR [g/U]
            carbs_hr = settingsManager.preferences.min5mCarbimpact * 12 / isf * cr
            if settingsManager.settings.units == .mmolL {
                carbs_hr = carbs_hr * GlucoseUnits.exchangeRate
            }
            // No, Decimal has no rounding function.
            carbs_hr = Decimal(round(Double(carbs_hr) * 10.0)) / 10
        }

        let ps = ScheduledNightscoutProfile(
            dia: settingsManager.pumpSettings.insulinActionCurve,
            carbs_hr: Int(carbs_hr),
            delay: 0,
            timezone: TimeZone.current.identifier,
            target_low: target_low,
            target_high: target_high,
            sens: sens,
            basal: basal,
            carbratio: cr,
            units: nsUnits
        )
        let defaultProfile = "default"

        let now = Date()
        let p = NightscoutProfileStore(
            defaultProfile: defaultProfile,
            startDate: now,
            mills: Int(now.timeIntervalSince1970) * 1000,
            units: nsUnits,
            enteredBy: NigtscoutTreatment.local,
            store: [defaultProfile: ps]
        )

        guard let nightscout = nightscoutAPI, isNetworkReachable, isUploadEnabled else {
            return
        }

        // UPLOAD PREFERNCES WHEN CHANGED
        if let uploadedPreferences = storage.retrieve(OpenAPS.Nightscout.uploadedPreferences, as: Preferences.self),
           uploadedPreferences.rawJSON.sorted() == preferences.rawJSON.sorted(), !force
        {
            NSLog("NightscoutManager Preferences, preferences unchanged")
        } else { uploadPreferences(preferences) }

        // UPLOAD FreeAPS Settings WHEN CHANGED
        if let uploadedSettings = storage.retrieve(OpenAPS.Nightscout.uploadedSettings, as: FreeAPSSettings.self),
           uploadedSettings.rawJSON.sorted() == settings.rawJSON.sorted(), !force
        {
            NSLog("NightscoutManager Settings, settings unchanged")
        } else { uploadSettings(settings) }

        // UPLOAD Profiles WHEN CHANGED
        if let uploadedProfile = storage.retrieve(OpenAPS.Nightscout.uploadedProfile, as: NightscoutProfileStore.self),
           (uploadedProfile.store["default"]?.rawJSON ?? "").sorted() == ps.rawJSON.sorted(), !force
        {
            NSLog("NightscoutManager uploadProfile, no profile change")
        } else {
            processQueue.async {
                nightscout.uploadProfile(p)
                    .sink { completion in
                        switch completion {
                        case .finished:
                            self.storage.save(p, as: OpenAPS.Nightscout.uploadedProfile)
                            debug(.nightscout, "Profile uploaded")
                        case let .failure(error):
                            debug(.nightscout, error.localizedDescription)
                        }
                    } receiveValue: {}
                    .store(in: &self.lifetime)
            }
        }
    }

    func uploadGlucose() {
        uploadGlucose(glucoseStorage.nightscoutGlucoseNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedGlucose)
        uploadTreatments(glucoseStorage.nightscoutCGMStateNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedCGMState)
    }

    func uploadManualGlucose() {
        uploadTreatments(
            glucoseStorage.nightscoutManualGlucoseNotUploaded(),
            fileToSave: OpenAPS.Nightscout.uploadedManualGlucose
        )
    }

    func editOverride(_ profile: String, _ duration_: Double, _ date: Date) {
        let duration = Int(duration_ == 0 ? 2880 : duration_)
        let exercise =
            [NigtscoutExercise(
                duration: duration,
                eventType: EventType.nsExercise,
                createdAt: date,
                enteredBy: NigtscoutTreatment.local,
                notes: profile
            )]

        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }

        processQueue.async {
            nightscout.deleteOverride(at: date)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Old Override deleted in NS, date: \(date)")
                        nightscout.uploadEcercises(exercise)
                            .sink { completion in
                                switch completion {
                                case .finished:
                                    debug(.nightscout, "Override Uploaded to NS, date: \(date)")
                                case let .failure(error):
                                    self.overrideStorage.addToNotUploaded(1)
                                    self.notUploaded(overrides: exercise)
                                    debug(.nightscout, "Upload of Override failed: " + error.localizedDescription)
                                }
                            } receiveValue: {}
                            .store(in: &self.lifetime)
                    case let .failure(error):
                        debug(.nightscout, "Deletion of Old Override failed: " + error.localizedDescription)
                        self.overrideStorage.addToNotUploaded(1)
                        self.notUploaded(overrides: exercise)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func uploadOverride(_ profile: String, _ duration_: Double, _ date: Date) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }
        let duration = Int(duration_ == 0 ? 2880 : duration_)

        let exercise =
            [NigtscoutExercise(
                duration: duration,
                eventType: EventType.nsExercise,
                createdAt: date,
                enteredBy: NigtscoutTreatment.local,
                notes: profile
            )]

        processQueue.async {
            nightscout.uploadEcercises(exercise)
                // nightscout.uploadTreatments(override)
                .sink { completion in
                    switch completion {
                    case .finished:
                        debug(.nightscout, "Override Uploaded to NS, date: \(date), override: \(exercise)")
                    case let .failure(error):
                        debug(.nightscout, "Upload of Override failed: " + error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    func deleteOverride() {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }
        nightscout.deleteNSoverride()
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "Override deleted in NS")
                case let .failure(error):
                    debug(.nightscout, "Override deletion in NS failed: " + error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    func deleteAllNSoverrrides() {
        guard let nightscout = nightscoutAPI, isUploadEnabled else {
            return
        }
        nightscout.deleteAllNSoverrrides()
            .sink { completion in
                switch completion {
                case .finished:
                    debug(.nightscout, "All Overrides deleted in NS")
                case let .failure(error):
                    debug(.nightscout, "Deletion of all overrides in NS failed: " + error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    private func notUploaded(overrides: [NigtscoutExercise]) {
        let file = OpenAPS.Nightscout.notUploadedOverrides
        var uniqEvents: [NigtscoutExercise] = []

        storage.transaction { storage in
            storage.append(overrides, to: file, uniqBy: \.createdAt)
            uniqEvents = storage.retrieve(file, as: [NigtscoutExercise].self)?
                .filter { $0.createdAt.addingTimeInterval(2.days.timeInterval) > Date() }
                .sorted { $0.createdAt > $1.createdAt } ?? []
            storage.save(Array(uniqEvents), as: file)
            debug(.nightscout, "\(uniqEvents.count) Overide added to list ot not uploaded Overrides.")
        }
    }

    private func removeFromNotUploaded() {
        let file = OpenAPS.Nightscout.notUploadedOverrides
        storage.transaction { storage in
            let newFile: [NigtscoutExercise] = []
            storage.save(newFile, as: file)
            debug(.nightscout, "Override(s) deleted from list of not uploaded Overrides.")
        }
    }

    private func uploadPumpHistory() {
        uploadTreatments(pumpHistoryStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedPumphistory)
    }

    private func uploadCarbs() {
        uploadTreatments(carbsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedCarbs)
    }

    private func uploadTempTargets() {
        uploadTreatments(tempTargetsStorage.nightscoutTretmentsNotUploaded(), fileToSave: OpenAPS.Nightscout.uploadedTempTargets)
    }

    private func uploadGlucose(_ glucose: [BloodGlucose], fileToSave: String) {
        guard !glucose.isEmpty, let nightscout = nightscoutAPI, isUploadEnabled, isUploadGlucoseEnabled else {
            return
        }
        // check if unique code
        // var uuid = UUID(uuidString: yourString) This will return nil if yourString is not a valid UUID
        let glucoseWithoutCorrectID = glucose.filter { UUID(uuidString: $0._id) != nil }

        processQueue.async {
            glucoseWithoutCorrectID.chunks(ofCount: 100)
                .map { chunk -> AnyPublisher<Void, Error> in
                    nightscout.uploadGlucose(Array(chunk))
                }
                .reduce(
                    Just(()).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                ) { (result, next) -> AnyPublisher<Void, Error> in
                    Publishers.Concatenate(prefix: result, suffix: next).eraseToAnyPublisher()
                }
                .dropFirst()
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(glucose, as: fileToSave)
                        debug(.nightscout, "Glucose uploaded")

                        // self.checkForNoneUploadedOverides() // To do : Move somewhere else

                    case let .failure(error):
                        debug(.nightscout, "Upload of glucose failed: " + error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }

    private func checkForNoneUploadedOverides() {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }
        guard let count = overrideStorage.countNotUploaded() else { return }

        let file = storage.retrieve(OpenAPS.Nightscout.notUploadedOverrides, as: [NigtscoutExercise].self) ?? []
        guard file.isNotEmpty else { return }

        let deleteLast = file[0] // To do: Not always needed, but try everytime for now...
        nightscout.deleteOverride(at: deleteLast.createdAt)
            .sink { completion in
                switch completion {
                case .finished:
                    self.removeFromNotUploaded()
                    self.overrideStorage.addToNotUploaded(0)
                    debug(.nightscout, "Last Override deleted from NS")
                case let .failure(error):
                    debug(.nightscout, "Last Override deleteion from NS failed! " + error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)

        nightscout.uploadEcercises(file)
            .sink { completion in
                switch completion {
                case .finished:
                    self.removeFromNotUploaded()
                    self.overrideStorage.addToNotUploaded(0)
                    debug(.nightscout, "\(count) Override(s) from list of not uploaded now uploaded!")
                case let .failure(error):
                    debug(.nightscout, "Upload of Override from list of not uploaded failed: " + error.localizedDescription)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    private func uploadTreatments(_ treatments: [NigtscoutTreatment], fileToSave: String) {
        guard let nightscout = nightscoutAPI, isUploadEnabled else { return }

        checkForNoneUploadedOverides() // To do : Move somewhere else

        guard !treatments.isEmpty else { return }

        processQueue.async {
            treatments.chunks(ofCount: 100)
                .map { chunk -> AnyPublisher<Void, Error> in
                    nightscout.uploadTreatments(Array(chunk))
                }
                .reduce(
                    Just(()).setFailureType(to: Error.self)
                        .eraseToAnyPublisher()
                ) { (result, next) -> AnyPublisher<Void, Error> in
                    Publishers.Concatenate(prefix: result, suffix: next).eraseToAnyPublisher()
                }
                .dropFirst()
                .sink { completion in
                    switch completion {
                    case .finished:
                        self.storage.save(treatments, as: fileToSave)
                        debug(.nightscout, "Treatments uploaded")
                    case let .failure(error):
                        debug(.nightscout, error.localizedDescription)
                    }
                } receiveValue: {}
                .store(in: &self.lifetime)
        }
    }
}

extension BaseNightscoutManager: PumpHistoryObserver {
    func pumpHistoryDidUpdate(_: [PumpHistoryEvent]) {
        uploadPumpHistory()
    }
}

extension BaseNightscoutManager: CarbsObserver {
    func carbsDidUpdate(_: [CarbsEntry]) {
        uploadCarbs()
    }
}

extension BaseNightscoutManager: TempTargetsObserver {
    func tempTargetsDidUpdate(_: [TempTarget]) {
        uploadTempTargets()
    }
}

extension BaseNightscoutManager: GlucoseObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        uploadManualGlucose()
    }
}
