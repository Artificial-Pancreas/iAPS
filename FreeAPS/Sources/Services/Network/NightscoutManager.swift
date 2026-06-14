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
    func uploadOldGlucose(bloodGlucose: [BloodGlucose]) async -> AsyncStream<Double>
    func uploadStatus() async
    func uploadProfileAndSettings(profile: NightscoutProfileStore?, force: Bool) async
    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async
    func deleteAnnouncements() async
    func deleteAllNSoverrrides() async
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
    private let storage: FileStorage
    private let announcementsStorage: AnnouncementsStorage
    private let settingsManager: SettingsManager
    private let reachabilityManager: ReachabilityManager
    private let healthkitManager: HealthKitManager

    private let overrideStorage = OverrideStorage()

    private var ping: TimeInterval?

    private var notUploadedOverrides: [NigtscoutExercise] = []

    private var lastSeenCgmStart: Date?
    private var cgmStartUploadPending: Bool = true

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
        self.storage = storage
        self.announcementsStorage = announcementsStorage
        self.settingsManager = settingsManager
        self.reachabilityManager = reachabilityManager
        self.healthkitManager = healthkitManager
    }

    // this is called at the start of the app
    func start() async {
        self.notUploadedOverrides = await storage
            .retrieve(OpenAPS.Nightscout.notUploadedOverrides, as: [NigtscoutExercise].self) ?? []

        observe(appCoordinator.carbHistoryUpdates) { me, carbHistory in
            await me.carbHistoryUpdated(carbHistory)
        }
        observe(appCoordinator.tempTargetsUpdates) { me, tempTargets in
            await me.tempTargetsUpdated(tempTargets)
        }
        observe(appCoordinator.glucoseHistoryUpdates) { me, bloodGlucose in
            await me.glucoseHistoryUpdated(bloodGlucose)
        }
        observe(appCoordinator.pumpHistoryUpdates) { me, pumpHistory in
            await me.pumpHistoryUpdated(pumpHistory)
        }
        observe(appCoordinator.cgmStatus) { me, cgmStatus in
            if let cgmStatus {
                await me.cgmStatusUpdated(cgmStatus)
            }
        }
        observe(appCoordinator.glucoseHistoryUpdates) { me, _ in
            // we are using glucoseHistoryUpdates only as a timer/trigger here, to retry uploading of overrides if needed
            await me.uploadOverridesIfNeeded()
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

        await uploadPodAge()
    }

    private func uploadPodAge() async {
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
            await syncTreatments(
                storedEvents: [siteTreatment],
                fileToSave: OpenAPS.Nightscout.uploadedPodAge,
                deletionPolicy: .appendOnly,
                uploadedRetention: .days(15) // keep 15 days in the .uploadedPodAge file to avoid unnecessary re-uploads of the same pod age
            )
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

    func uploadOldGlucose(bloodGlucose: [BloodGlucose]) async -> AsyncStream<Double> {
        let settings = appCoordinator.settings.value
        return uploadGlucose(
            upload: bloodGlucose,
            deleted: [],
            saveToUploaded: false, // do not update the "already uploaded glucose" file
            settings: settings
        )
    }

    private func pumpHistoryUpdated(_ pumpHistory: [PumpHistoryEvent]) async {
        let settings = appCoordinator.settings.value
        guard nightscoutAPI != nil, settings.isUploadEnabled, isNetworkReachable else {
            return
        }

        await syncTreatments(
            storedEvents: convertPumpHistoryToNightscout(events: pumpHistory),
            fileToSave: OpenAPS.Nightscout.uploadedPumphistory,
            deletionPolicy: .deleteMissing(within: .hours(23)),
            uploadedRetention: .hours(30)
        )
    }

    private func glucoseHistoryUpdated(_ bloodGlucose: [BloodGlucose]) async {
        let settings = appCoordinator.settings.value
        guard nightscoutAPI != nil, settings.isUploadEnabled, bloodGlucose.isNotEmpty, isNetworkReachable else {
            return
        }

        let storedEvents = bloodGlucose.sorted { $0.dateString > $1.dateString }

        let uploaded = await storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? []

        let notUploaded = Array(Set(bloodGlucose).subtracting(Set(uploaded)))

        let deletedFromStorage: [BloodGlucose]
        if let oldestStoredEventDate = storedEvents.reversed().first?.dateString {
            deletedFromStorage =
                Set(uploaded).subtracting(storedEvents)
                    .filter {
                        $0.dateString >= oldestStoredEventDate
                    }
        } else {
            deletedFromStorage = []
        }

        let deletedManualGlucose = deletedFromStorage.filter { $0.type == GlucoseType.manual.rawValue }

        await uploadGlucose(
            upload: notUploaded,
            deleted: deletedManualGlucose,
            saveToUploaded: true,
            settings: settings
        ).drain()
    }

    private func cgmStatusUpdated(_ cgmStatus: CgmDisplayStatus) async {
        // some optimizations here, to prevent reading the cgmState files every time
        let canUpload =
            nightscoutAPI != nil && appCoordinator.settings.value.isUploadEnabled && cgmStatus
                .shouldUploadGlucose && isNetworkReachable

        var cgmStateToUpload: [NigtscoutTreatment]?
        if let sessionStartDate = cgmStatus.sessionStartDate,
           abs(sessionStartDate.timeIntervalSince(lastSeenCgmStart ?? .distantPast)) > 60
        {
            self.lastSeenCgmStart = sessionStartDate

            if let cgmState = await recordSensorStartIfNeeded(sessionStartDate) {
                self.cgmStartUploadPending = true
                if canUpload {
                    cgmStateToUpload = cgmState
                }
            }
        }

        if canUpload, cgmStateToUpload == nil, self.cgmStartUploadPending {
            cgmStateToUpload = await readCgmState()
        }

        guard let cgmStateToUpload else {
            return
        }
        if cgmStateToUpload.isEmpty {
            cgmStartUploadPending = false
            return
        }
        if await syncTreatments(
            storedEvents: cgmStateToUpload,
            fileToSave: OpenAPS.Nightscout.uploadedCGMState,
            deletionPolicy: .appendOnly,
            uploadedRetention: .days(40) // we keep 30 days in .cgmState file, so we should keep >30 days in .uploadedCGMState
        ) != nil {
            // all uploaded
            self.cgmStartUploadPending = false
        }
    }

    private func recordSensorStartIfNeeded(_ sessionStartDate: Date) async -> [NigtscoutTreatment]? {
        let (didModify, modifiedCgmState) = await self.storage
            .maybeModify(file: OpenAPS.Monitor.cgmState, as: NigtscoutTreatment.self) { inStorage in
                // For Dexcom, each glucose event contains the sessionStartDate (which contains the correct timestamp of the latest sensor start)
                // We only need to send the "Sensor Start" event once per change.
                // This guard ensures we send a new "Sensor Start" event to NS only if the previously sent event happened more than 60 seconds before this one.
                //
                // As a side effect, if there is jitter in the sessionStartDate (+/- few milliseconds each time), we will flood NS with the duplicated Session Start events over time.
                // See: https://github.com/Artificial-Pancreas/iAPS/issues/1806
                if inStorage.contains(where: { abs($0.createdAt.timeIntervalSince(sessionStartDate)) < 60 }) {
                    return nil // do not modify
                }

                debug(.deviceManager, "CGM sensor change \(sessionStartDate)")

                let treatment = NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsSensorChange,
                    createdAt: sessionStartDate,
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

                var treatments = inStorage
                treatments.append(treatment)

                // We have to keep quite a bit of history as sensors start only every 10 days.
                let daysAgo30 = Date.now.removingTimeInterval(.days(30))
                return treatments
                    .filter { $0.createdAt >= daysAgo30 }
                    .sorted { $0.createdAt > $1.createdAt }
            }
        if didModify {
            return modifiedCgmState
        }
        return nil
    }

    func uploadOverride(_ profile: String, _ duration_: Double, _ date: Date) async {
        let duration = Int(duration_ == 0 ? 2880 : duration_)

        let exercise =
            [NigtscoutExercise(
                duration: duration,
                eventType: EventType.nsExercise,
                createdAt: date,
                enteredBy: NigtscoutTreatment.local,
                notes: profile
            )]

        await storeNotUploadedOverrides(exercise)
        await uploadOverridesIfNeeded()
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

    private func storeNotUploadedOverrides(_ overrides: [NigtscoutExercise]) async {
        self.notUploadedOverrides = await storage.appendAndModify(
            overrides,
            to: OpenAPS.Nightscout.notUploadedOverrides,
            uniqBy: \.createdAt
        ) {
            $0
                .filter { $0.createdAt.addingTimeInterval(2.days.timeInterval) > Date() }
                .sorted { $0.createdAt > $1.createdAt }
        }
        debug(.nightscout, "\(self.notUploadedOverrides.count) overrides saved for upload retry")
    }

    private func removeOverrideFromNotUploaded(at date: Date) async {
        self.notUploadedOverrides = self.notUploadedOverrides.filter { $0.createdAt != date }
        await storage.save(self.notUploadedOverrides, as: OpenAPS.Nightscout.notUploadedOverrides)
    }

    private func carbHistoryUpdated(_ carbHistory: [CarbsEntry]) async {
        let settings = appCoordinator.settings.value
        guard nightscoutAPI != nil, settings.isUploadEnabled, isNetworkReachable else {
            return
        }

        await syncTreatments(
            storedEvents: convertCarbHistoryToNightscout(events: carbHistory),
            fileToSave: OpenAPS.Nightscout.uploadedCarbs,
            deletionPolicy: .deleteMissing(within: .hours(23)),
            uploadedRetention: .hours(30)
        )
    }

    private func tempTargetsUpdated(_ tempTargets: [TempTarget]) async {
        let settings = appCoordinator.settings.value
        guard nightscoutAPI != nil, settings.isUploadEnabled, isNetworkReachable else {
            return
        }

        await syncTreatments(
            storedEvents: convertTempTargetsToNightscout(events: tempTargets),
            fileToSave: OpenAPS.Nightscout.uploadedTempTargets,
            deletionPolicy: .appendOnly,
            uploadedRetention: .hours(30)
        )
    }

    /// upload `glucose` to nightscout, upon success - if provided, append uploaded glucose to storage so we don't upload any of it next time
    private func uploadGlucose(
        upload glucose: [BloodGlucose],
        deleted: [BloodGlucose],
        saveToUploaded: Bool,
        settings: FreeAPSSettings
    ) -> AsyncStream<Double> {
        AsyncStream { continuation in
            Task {
                guard settings.isUploadEnabled, !glucose.isEmpty || !deleted.isEmpty, let nightscout = nightscoutAPI,
                      appCoordinator.cgmStatus.value?.shouldUploadGlucose == true
                else {
                    continuation.finish()
                    return
                }

                var deletedFromNightscout: [BloodGlucose] = []
                for deletedGlucose in deleted {
                    do {
                        try await nightscout.deleteManualGlucose(at: deletedGlucose.dateString)
                        deletedFromNightscout.append(deletedGlucose)
                        debug(.nightscout, "Manual Glucose entry deleted: \(deletedGlucose.dateString)")
                    } catch {
                        debug(
                            .nightscout,
                            "failed to delete manual glucose from nightscout: \(deletedGlucose.dateString) - \(error.localizedDescription)"
                        )
                    }
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
                    if saveToUploaded {
                        let deletedFromNightscoutDates = Set(deletedFromNightscout.map(\.dateString))
                        _ = await storage
                            .modify(file: OpenAPS.Nightscout.uploadedGlucose, as: BloodGlucose.self) { previousUploaded in
                                let dayAgo = Date.now.removingTimeInterval(.hours(25))
                                return (previousUploaded + glucose)
                                    .uniqued(on: \.dateString)
                                    .filter { entry in
                                        entry.dateString > dayAgo &&
                                            !deletedFromNightscoutDates.contains(entry.dateString)
                                    }
                            }
                    }
                    debug(.nightscout, "Glucose uploaded")

                } catch {
                    debug(.nightscout, "Upload of glucose failed: " + error.localizedDescription)
                }

                continuation.finish()
            }
        }
    }

    private var isUploadingOverrides = false

    private func uploadOverridesIfNeeded() async {
        guard notUploadedOverrides.isNotEmpty, let nightscout = nightscoutAPI,
              appCoordinator.settings.value.isUploadEnabled else { return }
        guard !isUploadingOverrides else { return }
        isUploadingOverrides = true
        defer { isUploadingOverrides = false }

        for override in notUploadedOverrides {
            do {
                try await nightscout.deleteOverride(at: override.createdAt)
                debug(.nightscout, "override deleted from NS before uploading: \(String(describing: override.notes))")
                try await nightscout.uploadEcercises([override])
                debug(.nightscout, "override uploaded to NS: \(String(describing: override.notes))")
                await removeOverrideFromNotUploaded(at: override.createdAt)
            } catch {
                debug(
                    .nightscout,
                    "failed to update override in NS: \(String(describing: override.notes)) - \(error.localizedDescription)"
                )
            }
        }
    }

    private enum DeletionPolicy {
        case appendOnly
        case deleteMissing(within: TimeInterval) // retention window
    }

    /// * read the snapshot of previously uploaded treatments from the file
    /// * detect new treatments in the current local data and upload them
    /// * detect previously uploaded treatments that are no longer present in the current local data (within retention window) and delete them
    /// * update the 'previously uploaded' file, removing entries older than `now-uploadedRetention`
    ///
    /// The invariant for the .deleteMissing(within) deletion policy:
    ///   within <= actual source retention < uploadedRetention
    ///
    /// For example, if deletionPolicy = .deleteMissing(.hours(23)):
    /// * the assumption is the current storage holds at least 23 hours of data
    /// * if there is a previously uploaded event, if this event is less than 23 hours old, and it is missing from the local data - it is assumed
    ///   to have been deleted locally after it's been uploaded, and it will be deleted from Nightscout.
    /// * events older than 23 hours, will not be deleted from nightscout even if deleted locally
    @discardableResult private func syncTreatments(
        storedEvents treatments: [NigtscoutTreatment],
        fileToSave: String,
        deletionPolicy: DeletionPolicy,
        uploadedRetention: TimeInterval
    ) async -> [NigtscoutTreatment]? {
        guard let nightscout = nightscoutAPI else { return nil }

        let previouslyUploaded = await storage.retrieve(fileToSave, as: [NigtscoutTreatment].self) ?? []
        let previouslyUploadedKeys = Set(previouslyUploaded.map(\.identity))

        let treatmentsToUpload = treatments.filter { !previouslyUploadedKeys.contains($0.identity) }
            .sorted { $0.createdAt > $1.createdAt }

        let storedKeys = Set(treatments.map(\.identity))
        let deletedFromStorage: [NigtscoutTreatment] = {
            switch deletionPolicy {
            case .appendOnly:
                return []
            case let .deleteMissing(retentionPeriod):
                let retentionCutoff = Date().removingTimeInterval(retentionPeriod)
                return previouslyUploaded.filter { !storedKeys.contains($0.identity) }
                    .filter {
                        $0.createdAt >= retentionCutoff
                    }
            }
        }()

        guard treatments.isNotEmpty || deletedFromStorage.isNotEmpty else {
            return nil
        }

        let eventTypes = (treatments.map(\.eventType) + deletedFromStorage.map(\.eventType)).uniqued().map(\.rawValue)
            .joined(separator: ", ")

        do {
            var deletedFromNS: [NigtscoutTreatment] = []
            for treatment in deletedFromStorage {
                do {
                    try await nightscout.deleteTreatment(treatment)
                    deletedFromNS.append(treatment)
                } catch {
                    debug(
                        .nightscout,
                        "failed to delete \(treatment.eventType) treatment from NS: \(treatment.eventType) \(String(describing: treatment.createdAt))"
                    )
                }
            }

            for chunk in treatmentsToUpload.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            debug(
                .nightscout,
                "treatments uploaded - \(eventTypes): \(treatmentsToUpload.count), deleted: \(deletedFromNS.count)"
            )

            let cutoff = Date().removingTimeInterval(uploadedRetention)
            let deletedFromNSKeys = Set(deletedFromNS.map(\.identity))
            return await storage.modify(file: fileToSave, as: NigtscoutTreatment.self) { previouslyUploaded in
                let oldAndNewUploaded = (previouslyUploaded + treatmentsToUpload)
                    .filter { !deletedFromNSKeys.contains($0.identity) }

                // newest -> oldest
                return oldAndNewUploaded
                    // only store events not older than uploadedRetention, but keep everything that is present in storage to avoid re-uploads
                    .filter { $0.createdAt >= cutoff || storedKeys.contains($0.identity) }
                    .sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
        return nil
    }

    private func readCgmState() async -> [NigtscoutTreatment] {
        let (_, cgmState) = await storage
            .maybeModify(file: OpenAPS.Monitor.cgmState, as: NigtscoutTreatment.self) { cgmState in
                // filter older cgm entries on read
                let daysAgo30 = Date.now.removingTimeInterval(.days(30))
                let last30days = cgmState.filter { $0.createdAt >= daysAgo30 }
                if last30days.count == cgmState.count {
                    return nil // do not modify
                }
                return last30days // save with older-than-30-days entries removed
            }

        return cgmState
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

extension BaseNightscoutManager {
    /// returns events converted to nightscout format, oldest -> newest
    private func convertPumpHistoryToNightscout(events: [PumpHistoryEvent]) -> [NigtscoutTreatment] {
        guard !events.isEmpty else { return [] }

        let temps: [NigtscoutTreatment] = events.reduce([]) { result, event in
            var result = result
            switch event.type {
            case .tempBasal:
                result.append(NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: event,
                    absolute: event.rate,
                    rate: event.rate,
                    eventType: .nsTempBasal,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                ))
            case .tempBasalDuration:
                if var last = result.popLast(), last.eventType == .nsTempBasal, last.createdAt == event.timestamp {
                    last.duration = event.durationMin
                    last.rawDuration = event
                    result.append(last)
                }
            default: break
            }
            return result
        }

        let bolusesAndCarbs = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .bolus:
                let eventType = determineBolusEventType(for: event)
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: eventType,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: event.amount,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .journalCarbs:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: Decimal(event.carbInput ?? 0),
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil,
                    creation_date: event.timestamp
                )
            default: return nil
            }
        }

        let misc = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .prime:
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsSiteChange,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .rewind:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsInsulinChange,
                    createdAt: event.timestamp,
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
            case .pumpAlarm:
                return NigtscoutTreatment(
                    duration: 30, // minutes
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsAnnouncement,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: "Alarm \(String(describing: event.note)) \(event.type)",
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            default: return nil
            }
        }

        return (bolusesAndCarbs + temps + misc).sorted { $0.createdAt > $1.createdAt }
    }

    private func determineBolusEventType(for event: PumpHistoryEvent) -> EventType {
        if event.isSMB ?? false {
            return .smb
        }
        if event.isExternal ?? false {
            return .isExternal
        }
        return event.type
    }
}

extension BaseNightscoutManager {
    /// returns events converted to nightscout format, newest -> oldest
    private func convertCarbHistoryToNightscout(events: [CarbsEntry]) -> [NigtscoutTreatment] {
        let eventsManual = events
            .filter {
                ($0.enteredBy == CarbsEntry.manual || $0.enteredBy == CarbsEntry.remote || $0.enteredBy == CarbsEntry.shortcut) &&
                    $0.carbs > 0 }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.actualDate ?? .distantPast,
                enteredBy: $0.enteredBy ?? CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                carbs: $0.carbs,
                fat: nil,
                protein: nil,
                foodType: $0.note,
                targetTop: nil,
                targetBottom: nil,
                id: $0.id,
                fpuID: nil,
                creation_date: $0.createdAt
            )
        }
        return treatments.sorted { $0.createdAt > $1.createdAt }
    }
}

extension BaseNightscoutManager {
    /// returns temp targets converted to nightscout format, newest -> oldest
    private func convertTempTargetsToNightscout(events: [TempTarget]) -> [NigtscoutTreatment] {
        let eventsManual = events.filter { $0.enteredBy == TempTarget.manual }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: Int($0.duration),
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsTempTarget,
                createdAt: $0.createdAt,
                enteredBy: TempTarget.manual,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: nil,
                targetTop: $0.targetTop,
                targetBottom: $0.targetBottom
            )
        }
        return treatments.sorted { $0.createdAt > $1.createdAt }
    }
}

private extension AsyncSequence {
    func drain() async rethrows {
        for try await _ in self {}
    }
}

private struct NigtscoutTreatmentIdentity: Equatable, Hashable {
    let eventType: EventType
    let createdAt: Date
}

private extension NigtscoutTreatment {
    var identity: NigtscoutTreatmentIdentity {
        NigtscoutTreatmentIdentity(
            eventType: eventType,
            createdAt: createdAt
        )
    }
}
