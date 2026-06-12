import Foundation
import NightscoutKit
import Swinject
import UIKit

protocol NightscoutManager: Sendable {
    func isConfigured() async -> Bool
    func fetchGlucose(since date: Date) async -> AsyncStream<FetchGlucoseProgress>
    func fetchCarbs() async -> [CarbsEntry]
    func fetchTempTargets() async -> [TempTarget]
    func fetchAnnouncements() async -> [Announcement]
    func deleteCarbs(_ date: Date) async
    func deleteInsulin(at date: Date) async
    func deleteManualGlucose(at: Date) async
    func uploadOldGlucose(bloodGlucose: [BloodGlucose]) async -> AsyncStream<Double>
    func uploadStatus() async
    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async
    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async
    func deleteAnnouncements() async
    func deleteAllNSoverrrides() async
    func deleteOverride() async
    func editOverride(_ profile: String, _ duration_: Double, _ date: Date) async
    func fetchProfile() async throws -> [FetchedNightscoutProfileStore]
}

enum FetchGlucoseProgress {
    case progress(Double)
    case done([BloodGlucose])
}

actor BaseNightscoutManager: NightscoutManager, LifetimeOwner, AppService {
    private let keychain: Keychain
    private let appCoordinator: AppCoordinator
    private let glucoseStorage: GlucoseStorage
    private let tempTargetsStorage: TempTargetsStorage
    private let carbsStorage: CarbsStorage
    private let pumpHistoryStorage: PumpHistoryStorage
    private let storage: FileStorage
    private let announcementsStorage: AnnouncementsStorage
    private let settingsManager: SettingsManager
    private let reachabilityManager: ReachabilityManager
    private let healthkitManager: HealthKitManager

    private let overrideStorage = OverrideStorage()

    private var ping: TimeInterval?

    let lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
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

    init(
        keychain: Keychain,
        appCoordinator: AppCoordinator,
        glucoseStorage: GlucoseStorage,
        tempTargetsStorage: TempTargetsStorage,
        carbsStorage: CarbsStorage,
        pumpHistoryStorage: PumpHistoryStorage,
        storage: FileStorage,
        announcementsStorage: AnnouncementsStorage,
        settingsManager: SettingsManager,
        reachabilityManager: ReachabilityManager,
        healthkitManager: HealthKitManager
    ) {
        self.keychain = keychain
        self.appCoordinator = appCoordinator
        self.glucoseStorage = glucoseStorage
        self.tempTargetsStorage = tempTargetsStorage
        self.carbsStorage = carbsStorage
        self.pumpHistoryStorage = pumpHistoryStorage
        self.storage = storage
        self.announcementsStorage = announcementsStorage
        self.settingsManager = settingsManager
        self.reachabilityManager = reachabilityManager
        self.healthkitManager = healthkitManager
    }

    // this is called at the start of the app
    func start() async {
        // TODO: use values from the stream instead of re-reading the files?..
        observe(appCoordinator.pumpHistoryUpdates) { me, _ in
            await me.uploadPumpHistory()
        }
        observe(appCoordinator.carbHistoryUpdates) { me, _ in
            await me.uploadCarbs()
        }
        observe(appCoordinator.tempTargetsUpdates) { me, _ in
            await me.uploadTempTargets()
        }
        observe(appCoordinator.glucoseHistoryUpdates) { me, bloodGlucose in
            await me.uploadGlucose(bloodGlucose: bloodGlucose)
        }
    }

    func isConfigured() async -> Bool {
        nightscoutAPI != nil
    }

    func sourceInfo() -> [String: Any]? {
        if let ping = ping {
            return [GlucoseSourceKey.nightscoutPing.rawValue: ping]
        }
        return nil
    }

    func fetchGlucose(since sinceDate: Date) async -> AsyncStream<FetchGlucoseProgress> {
        AsyncStream { continuation in
            Task {
                ping = nil

                guard let nightscout = nightscoutAPI, isNetworkReachable else {
                    continuation.yield(.done([]))
                    continuation.finish()
                    return
                }

                let startDate = Date()
                let secondsToFetch = Double(startDate.timeIntervalSince1970 - sinceDate.timeIntervalSince1970)

                var acc: [BloodGlucose] = []

                var until = Date.now.addingTimeInterval(10 * 60)

                while true {
                    debug(
                        .nightscout,
                        "requesting glucose records page from nightscout: \(sinceDate) .. \(String(describing: until))"
                    )
                    let chunk = await nightscout.fetchGlucose(dateInterval: DateInterval(start: sinceDate, end: until))

                    guard let oldest = chunk.min(by: { $0.date < $1.date }) else {
                        continuation.yield(.progress(100.0))
                        break
                    }

                    acc += chunk.filter { $0.date > sinceDate }.compactMap { BloodGlucose.from(nightscout: $0) }

                    if oldest.date <= sinceDate {
                        continuation.yield(.progress(100.0))
                        break
                    }

                    let secondsFetched = Double(startDate.timeIntervalSince1970 - oldest.date.timeIntervalSince1970)
                    if secondsToFetch > 0 {
                        continuation.yield(.progress((secondsFetched / secondsToFetch).clamped(0.0 ... 100.0)))
                    }

                    until = oldest.date
                        .addingTimeInterval(-0.001) // the fetch is inclusive, so we set until to the oldest entrie's date minus 1 millisecond
                }

                if acc.isNotEmpty {
                    ping = Date().timeIntervalSince(startDate)
                }

                continuation.yield(.done(acc))
                continuation.finish()
            }
        }
    }

    func fetchCarbs() async -> [CarbsEntry] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }

        let since = await carbsStorage.syncDate()
        return await nightscout.fetchCarbs(sinceDate: since)
    }

    func fetchTempTargets() async -> [TempTarget] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }

        let since = await tempTargetsStorage.syncDate()
        return await nightscout.fetchTempTargets(sinceDate: since)
    }

    func fetchAnnouncements() async -> [Announcement] {
        guard let nightscout = nightscoutAPI, isNetworkReachable else {
            return []
        }
        let since = await announcementsStorage.syncDate()
        return await nightscout.fetchAnnouncement(sinceDate: since)
    }

    func deleteCarbs(_ date: Date) async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            // TODO: what is this?
            await carbsStorage.deleteCarbsAndFPUs(at: date)
            await healthkitManager.deleteCarbs(date: date)
            return
        }

        await healthkitManager.deleteCarbs(date: date)
        await carbsStorage.deleteCarbsAndFPUs(at: date)

        do {
            try await nightscout.deleteCarbs(date)
            debug(.nightscout, "Carbs with date \(date) deleted from NS.")
        } catch {
            info(
                .nightscout,
                "Deletion of carbs in NightScout not done \n \(error.localizedDescription)",
                type: MessageType.warning
            )
        }
    }

    func deleteAnnouncements() async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }
        do {
            try await nightscout.deleteAnnouncements()
            debug(.nightscout, "Annuncement(s) deleted from NS.")
        } catch {
            info(
                .nightscout,
                "Deletion of Announcements not possible \(error.localizedDescription)",
                type: MessageType.warning
            )
        }
    }

    func deleteInsulin(at date: Date) async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            // TODO: what is this?
            await pumpHistoryStorage.deleteInsulin(at: date)
            return
        }

        do {
            try await nightscout.deleteInsulin(at: date)
            await pumpHistoryStorage.deleteInsulin(at: date)
            debug(.nightscout, "Insulin deleted from NS")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    func deleteManualGlucose(at date: Date) async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }
        do {
            try await nightscout.deleteManualGlucose(at: date)
            debug(.nightscout, "Manual Glucose entry deleted")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    func uploadStatus() async {
        let settings = appCoordinator.settings.value
        let iob = await storage.retrieve(OpenAPS.Monitor.iob, as: [IOBEntry].self)
        var suggested = await storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)
        var enacted = await storage.retrieve(OpenAPS.Enact.enacted, as: Suggestion.self)

        if (suggested?.timestamp ?? .distantPast) > (enacted?.timestamp ?? .distantPast) {
            enacted?.predictions = nil
        } else {
            suggested?.predictions = nil
        }

        let loopIsClosed = settings.closedLoop

        var openapsStatus: OpenAPSStatus

        // Nightscout requires both enacted and suggested fields to show popup on graph
        // When we have enacted, also send suggested with same content
        if loopIsClosed {
            openapsStatus = OpenAPSStatus(
                iob: iob?.first,
                suggested: enacted,
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

        let battery = appCoordinator.pumpStatus.value?.battery
        let pumpReservoir = appCoordinator.pumpReservoir.value
        let reservoir: Decimal?

        if case let .units(units) = pumpReservoir {
            reservoir = units
        } else {
            reservoir = nil
        }

        //  await storage.retrieve(OpenAPS.Monitor.status, as: PumpStatus.self)
        let pumpStatus = appCoordinator.pumpStatus.value.map { pumpStatus in
            NSPumpStatusDetails(
                status: NSStatusType(rawValue: pumpStatus.status.rawValue) ?? .normal,
                bolusing: pumpStatus.isBolusing,
                suspended: pumpStatus.isSuspended,
                timestamp: pumpStatus.timestamp,
            )
        }

        let pump = NSPumpStatus(
            clock: Date(),
            battery: battery,
            reservoir: reservoir,
            status: pumpStatus
        )

        let device = await UIDevice.current
        let batteryLevel = await device.batteryLevel
        let uploader = Uploader(batteryVoltage: nil, battery: Int(batteryLevel * 100))

        // Use latest SGV timestamp to match devicestatus with SGV entries
        let latestGlucoseDate = await glucoseStorage.latestDate() ?? Date()

        let status = NightscoutStatus(
            device: NigtscoutTreatment.local,
            openaps: openapsStatus,
            pump: pump,
            uploader: uploader,
            createdAt: latestGlucoseDate
        )

        await storage.save(status, as: OpenAPS.Upload.nsStatus)

        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }

        do {
            try await nightscout.uploadStatus(status)
            debug(.nightscout, "Status uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }

        await uploadPodAge(settings: settings)
    }

    private func uploadPodAge(settings: FreeAPSSettings) async {
        let uploadedPodAge = await storage.retrieve(OpenAPS.Nightscout.uploadedPodAge, as: [NigtscoutTreatment].self) ?? []
        if let podAge = appCoordinator.pumpInfo.value?.podActivatedAt,
           uploadedPodAge.last?.createdAt != podAge
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
            await uploadTreatments([siteTreatment], fileToSave: OpenAPS.Nightscout.uploadedPodAge, settings: settings)
        }
    }

    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async {
        let settings = appCoordinator.settings.value
        guard settings.isUploadEnabled,
              let profile,
              let ps = profile.store[profile.defaultProfile],
              let ns = nightscoutAPI
        else { return }

        let uploadedProfile = await storage.retrieveFile(OpenAPS.Nightscout.uploadedProfile, as: NightscoutProfileStore.self)
        // UPLOAD Profiles WHEN CHANGED
        if uploadedProfile?.store["default"] != ps || force {
            do {
                try await ns.uploadProfile(profile)
                await storage.save(profile, as: OpenAPS.Nightscout.uploadedProfile)
                debug(.nightscout, "Profile uploaded")
            } catch {
                debug(.nightscout, error.localizedDescription)
            }
        } else {
            debug(.nightscout, "uploadProfile, no profile change")
        }
    }

    private func nightscoutGlucoseNotUploaded(bloodGlucose: [BloodGlucose]) async -> [BloodGlucose] {
        let uploaded = await storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? []
        let glucoseToUpload = Array(Set(bloodGlucose).subtracting(Set(uploaded)))
        return glucoseToUpload
    }

    private func nightscoutCGMStateNotUploaded() async -> [NigtscoutTreatment] {
        let uploaded = await storage.retrieve(OpenAPS.Nightscout.uploadedCGMState, as: [NigtscoutTreatment].self) ?? []
        let recent = await storage.retrieve(OpenAPS.Monitor.cgmState, as: [NigtscoutTreatment].self) ?? []
        return Array(Set(recent).subtracting(Set(uploaded)))
    }

    func uploadOldGlucose(bloodGlucose: [BloodGlucose]) async -> AsyncStream<Double> {
        let settings = appCoordinator.settings.value
        return uploadGlucose(
            upload: bloodGlucose,
            allGlucose: nil, // do not update the "already uploaded glucose" file
            fileToSave: OpenAPS.Nightscout.uploadedGlucose,
            settings: settings
        )
    }

    private func uploadGlucose(bloodGlucose: [BloodGlucose]) async {
        let settings = appCoordinator.settings.value
        guard settings.isUploadEnabled, bloodGlucose.isNotEmpty, nightscoutAPI != nil else {
            return
        }

        let glucoseNotYetUploaded = await nightscoutGlucoseNotUploaded(bloodGlucose: bloodGlucose)

        await uploadGlucose(
            upload: glucoseNotYetUploaded,
            allGlucose: bloodGlucose,
            fileToSave: OpenAPS.Nightscout.uploadedGlucose,
            settings: settings
        ).drain()

        let cgmStateNotUploaded = await nightscoutCGMStateNotUploaded()
        await uploadTreatments(cgmStateNotUploaded, fileToSave: OpenAPS.Nightscout.uploadedCGMState, settings: settings)
    }

    func editOverride(_ profile: String, _ duration_: Double, _ date: Date) async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
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

        do {
            try await nightscout.deleteOverride(at: date)
            debug(.nightscout, "Old Override deleted in NS, date: \(date)")

            do {
                try await nightscout.uploadEcercises(exercise)
                debug(.nightscout, "Override Uploaded to NS, date: \(date)")
            } catch {
                // TODO: why is this "counter" needed?
                overrideStorage.addToNotUploaded(1)
                await notUploaded(overrides: exercise)
                debug(.nightscout, "Upload of Override failed: " + error.localizedDescription)
            }
        } catch {
            debug(.nightscout, "Deletion of Old Override failed: " + error.localizedDescription)
            // TODO: why is this "counter" needed?
            overrideStorage.addToNotUploaded(1)
            await notUploaded(overrides: exercise)
        }
    }

    func uploadOverride(_ profile: String, _ duration_: Double, _ date: Date) async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
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

        do {
            try await nightscout.uploadEcercises(exercise)
            // nightscout.uploadTreatments(override)
            debug(.nightscout, "Override Uploaded to NS, date: \(date), override: \(exercise)")
        } catch {
            debug(.nightscout, "Upload of Override failed: " + error.localizedDescription)
        }
    }

    func deleteOverride() async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }

        do {
            try await nightscout.deleteNSoverride()
            debug(.nightscout, "Override deleted in NS")
        } catch {
            debug(.nightscout, "Override deletion in NS failed: " + error.localizedDescription)
        }
    }

    func deleteAllNSoverrrides() async {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }
        do {
            try await nightscout.deleteAllNSoverrrides()
            debug(.nightscout, "All Overrides deleted in NS")
        } catch {
            debug(.nightscout, "Deletion of all overrides in NS failed: " + error.localizedDescription)
        }
    }

    func fetchProfile() async throws -> [FetchedNightscoutProfileStore] {
        guard let nightscout = nightscoutAPI else {
            return []
        }
        return try await nightscout.fetchProfile()
    }

    private func notUploaded(overrides: [NigtscoutExercise]) async {
        let file = OpenAPS.Nightscout.notUploadedOverrides
        let uniqEvents: [NigtscoutExercise] = await storage.appendAndModify(overrides, to: file, uniqBy: \.createdAt) {
            $0
                .filter { $0.createdAt.addingTimeInterval(2.days.timeInterval) > Date() }
                .sorted { $0.createdAt > $1.createdAt }
        }
        debug(.nightscout, "\(uniqEvents.count) Overide added to list ot not uploaded Overrides.")
    }

    private func removeFromNotUploaded() async {
        let file = OpenAPS.Nightscout.notUploadedOverrides
        let newFile: [NigtscoutExercise] = []
        await storage.save(newFile, as: file)
        debug(.nightscout, "Override(s) deleted from list of not uploaded Overrides.")
    }

    private func uploadPumpHistory() async {
        let settings = appCoordinator.settings.value
        let notUploaded = await pumpHistoryStorage.nightscoutTretmentsNotUploaded()
        await uploadTreatments(notUploaded, fileToSave: OpenAPS.Nightscout.uploadedPumphistory, settings: settings)
    }

    private func uploadCarbs() async {
        let settings = appCoordinator.settings.value
        let notUploaded = await carbsStorage.nightscoutTretmentsNotUploaded()
        await uploadTreatments(notUploaded, fileToSave: OpenAPS.Nightscout.uploadedCarbs, settings: settings)
    }

    private func uploadTempTargets() async {
        let settings = appCoordinator.settings.value
        let notUploaded = await tempTargetsStorage.nightscoutTretmentsNotUploaded()
        await uploadTreatments(notUploaded, fileToSave: OpenAPS.Nightscout.uploadedTempTargets, settings: settings)
    }

    /// upload `glucose` to nightscout, upon success - if provided, save `allGlucose` to storage so we don't upload any of it next time
    private func uploadGlucose(
        upload glucose: [BloodGlucose],
        allGlucose: [BloodGlucose]?,
        fileToSave: String,
        settings: FreeAPSSettings
    ) -> AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                guard settings.isUploadEnabled, !glucose.isEmpty, let nightscout = nightscoutAPI,
                      appCoordinator.cgmStatus.value?.shouldUploadGlucose == true
                else {
                    continuation.finish()
                    return
                }
                // check if unique code
                // var uuid = UUID(uuidString: yourString) This will return nil if yourString is not a valid UUID
                let glucoseWithCorrectID = glucose.filter { UUID(uuidString: $0._id) != nil }
                let total = glucoseWithCorrectID.count
                var uploaded = 0
                continuation.yield(0.0)

                do {
                    for chunk in glucoseWithCorrectID.chunks(ofCount: 100) {
                        let entries = chunk.compactMap(\.toNightscoutEntry)
                        _ = try await nightscout.uploadGlucose(Array(entries))
                        uploaded += chunk.count
                        if total != 0 {
                            continuation.yield(Double(uploaded) / Double(total))
                        } else {
                            continuation.yield(1.0)
                        }
                    }
                    if let allGlucose {
                        await storage.save(allGlucose, as: fileToSave)
                    }
                    debug(.nightscout, "Glucose uploaded")

                } catch {
                    debug(.nightscout, "Upload of glucose failed: " + error.localizedDescription)
                }

                continuation.finish()
            }
        }
    }

    private func checkForNotUploadedOverides(settings: FreeAPSSettings) async {
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else { return }
        // TODO: why is this "counter" needed?
//        guard let count = overrideStorage.countNotUploaded () else { return }

        let file = await storage.retrieve(OpenAPS.Nightscout.notUploadedOverrides, as: [NigtscoutExercise].self) ?? []
        guard file.isNotEmpty else { return }

        let deleteLast = file[0] // To do: Not always needed, but try everytime for now...
        do {
            try await nightscout.deleteOverride(at: deleteLast.createdAt)
            debug(.nightscout, "the last override deleted from NS")
        } catch {
            debug(.nightscout, "failed to delete the last override from NS: \(error.localizedDescription)")
        }

        do {
            try await nightscout.uploadEcercises(file)
            await removeFromNotUploaded()
            // TODO: why is this "counter" needed?
            overrideStorage.addToNotUploaded(0)
            debug(.nightscout, "uploaded \(file.count) override(s) to NS")
        } catch {
            debug(.nightscout, "failed to upload override(s) to NS: \(error.localizedDescription)")
        }
    }

    private func uploadTreatments(_ treatments: [NigtscoutTreatment], fileToSave: String, settings: FreeAPSSettings) async {
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else { return }

        await checkForNotUploadedOverides(settings: settings)

        guard !treatments.isEmpty else { return }

        do {
            for chunk in treatments.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }
            let oldUploaded = await storage.retrieve(fileToSave, as: [NigtscoutTreatment].self) ?? []
            let cutoff = Date().addingTimeInterval(-TimeInterval(hours: 30))
            let oldAndNewUploaded = (oldUploaded + treatments).filter { treatment in
                guard let createdAt = treatment.createdAt else { return false }
                return createdAt >= cutoff
            }
            await storage.save(oldAndNewUploaded, as: fileToSave)
            debug(.nightscout, "Treatments uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }
}

private extension BloodGlucose {
    static func from(nightscout entry: GlucoseEntry) -> BloodGlucose? {
        guard let id = entry.id else { return nil }
        let direction = (entry.trend?.direction).flatMap { BloodGlucose.Direction(rawValue: $0) }
        let glucose = Int(entry.glucose.rounded())
        let glucoseDecimal = Decimal(entry.glucose.rounded())
        let type: String?
        switch entry.glucoseType {
        case .sensor: type = "sgv"
        case .meter: type = "mbg"
        }
        return BloodGlucose(
            _id: id,
            sgv: glucose,
            direction: direction,
            date: Decimal(entry.date.timeIntervalSince1970 * 1000),
            dateString: entry.date,
            unfiltered: glucoseDecimal,
            uncalibrated: glucoseDecimal,
            filtered: nil,
            noise: nil,
            glucose: glucose,
            type: type,
            activationDate: nil,
            sessionStartDate: nil,
            transmitterID: nil,
            device: entry.device,
        )
    }

    var toNightscoutEntry: GlucoseEntry? {
        guard let glucose = (unfiltered.map { Double($0) } ?? sgv.map { Double($0) }) else { return nil }

        let glucoseType: GlucoseEntry.GlucoseType
        let isCalibration: Bool
        if type == GlucoseType.manual.rawValue {
            glucoseType = .meter
            isCalibration = false
        } else if type == GlucoseType.sgv.rawValue {
            glucoseType = .sensor
            isCalibration = false
        } else if type == GlucoseType.cal.rawValue {
            glucoseType = .meter
            isCalibration = true
        } else {
            return nil
        }

        let trend: GlucoseEntry.GlucoseTrend? = direction.flatMap { Self.trendFromDirection($0.rawValue) }

        return GlucoseEntry(
            glucose: glucose,
            date: dateString,
            device: device,
            glucoseType: glucoseType,
            trend: trend,
            changeRate: nil,
            isCalibration: isCalibration,
            condition: nil,
            id: id
        )
    }

    private static func trendFromDirection(_ direction: String?) -> GlucoseEntry.GlucoseTrend? {
        for trend in GlucoseEntry.GlucoseTrend.allCases {
            if direction == trend.direction {
                return trend
            }
        }
        return nil
    }
}

private extension AsyncSequence {
    func drain() async rethrows {
        for try await _ in self {}
    }
}
