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
    private var deletedGlucosePending: Bool = true
    private var deletedCarbsPending: Bool = true
    private var deletedPumpHistoryPending: Bool = true

    private var lastUploadedPodAge: Date?

    private var lastUploadedPumpStatus: PumpDisplayStatus?

    private let iapsVersion = Bundle.main.releaseVersionNumber ?? "Unknown"

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

        observe(appCoordinator.carbHistory) { me, carbHistory in
            await me.carbHistoryUpdated(carbHistory)
            // retry previous deletions if needed
            await me.carbsDeleted([])
        }
        observe(appCoordinator.carbDeletions) { me, deleted in
            await me.carbsDeleted(deleted)
        }

        observe(appCoordinator.tempTargets) { me, tempTargets in
            await me.tempTargetsUpdated(tempTargets)
        }

        observe(appCoordinator.glucoseHistory) { me, bloodGlucose in
            await me.glucoseHistoryUpdated(bloodGlucose)
            // retry previous deletions if needed
            await me.glucoseDeleted([])
        }
        observe(appCoordinator.glucoseDeletions) { me, deleted in
            await me.glucoseDeleted(deleted)
        }

        observe(appCoordinator.pumpHistory) { me, pumpHistory in
            await me.pumpHistoryUpdated(pumpHistory)
            // retry previous deletions if needed
            await me.pumpHistoryDeleted([])
        }
        observe(appCoordinator.pumpHistoryDeletions) { me, deleted in
            await me.pumpHistoryDeleted(deleted)
        }

        observe(appCoordinator.cgmStatus) { me, cgmStatus in
            if let cgmStatus {
                await me.cgmStatusUpdated(cgmStatus)
            }
        }

        observe(appCoordinator.pumpStatus) { me, pumpStatus in
            if let pumpStatus {
                await me.pumpStatusUpdated(pumpStatus)
            }
        }
        observe(appCoordinator.pumpInfo.map(\.?.podActivatedAt)) { me, podActivatedAt in
            if let podActivatedAt {
                await me.uploadPodAge(podActivatedAt: podActivatedAt)
            }
        }

        observe(appCoordinator.loopCompleted) { me, outcome in
            await me.loopCompleted(outcome)
        }

        observe(appCoordinator.iobTicks.dropFirst()) { me, iobTicks in
            if let iobTicks {
                await me.uploadIOB(iobTicks)
            }
        }

        observe(appCoordinator.loopCompleted) { me, _ in
            // we are using loopCompleted only as a timer/trigger here, to retry uploading of overrides if needed
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

    private func shouldUploadPumpStatusNow(_ pumpStatus: PumpDisplayStatus) -> Bool {
        guard let lastUploadedPumpStatus else { return true }
        if Date.now.timeIntervalSince(lastUploadedPumpStatus.timestamp) >= .minutes(5) {
            return true
        }
        return lastUploadedPumpStatus.isSuspended != pumpStatus.isSuspended ||
            lastUploadedPumpStatus.isBolusing != pumpStatus.isBolusing ||
            lastUploadedPumpStatus.status != pumpStatus.status ||
            lastUploadedPumpStatus.statusHighlight != pumpStatus.statusHighlight
    }

    private func pumpStatusUpdated(_ pumpStatus: PumpDisplayStatus) async {
        // do not flood nightscout
        guard shouldUploadPumpStatusNow(pumpStatus) else { return }

        let settings = appCoordinator.settings.value

        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }

        let battery = pumpStatus.battery

        let reservoir = pumpStatus.reservoir?.knownValue

        let nsPumpStatus =
            NSPumpStatusDetails(
                status: NSStatusType(rawValue: pumpStatus.status.rawValue) ?? .normal,
                bolusing: pumpStatus.isBolusing,
                suspended: pumpStatus.isSuspended,
                timestamp: pumpStatus.timestamp,
            )

        let pump = NSPumpStatus(
            clock: pumpStatus.timestamp,
            battery: battery,
            reservoir: reservoir,
            status: nsPumpStatus
        )

        let device = await UIDevice.current
        let batteryLevel = await device.batteryLevel
        let uploader = Uploader(batteryVoltage: nil, battery: Int(batteryLevel * 100))

        let status = NightscoutStatus(
            device: NigtscoutTreatment.local,
            openaps: nil,
            pump: pump,
            uploader: uploader,
            createdAt: pumpStatus.timestamp
        )

        do {
            try await nightscout.uploadStatus(status)
            lastUploadedPumpStatus = pumpStatus
            debug(.nightscout, "pump status uploaded")
        } catch {
            debug(.nightscout, "failed to upload pump status: \(error.localizedDescription)")
        }
    }

    private func loopCompleted(_ outcome: LoopOutcome) async {
        let recentSuggested: [Suggestion]
        let recentEnacted: [Suggestion]

        let hoursAgo30 = Date.now.removingTimeInterval(.hours(30))

        switch outcome {
        case let .enacted(suggestion, _):
            recentEnacted = await storage.appendAndModify([suggestion], to: OpenAPS.Upload.recentEnacted, uniqBy: \.timestamp) {
                $0.filter { ($0.timestamp ?? .distantPast) >= hoursAgo30 }
            }

            recentSuggested = await storage.retrieve(OpenAPS.Upload.recentSuggested, as: [Suggestion].self) ?? []
        case .enactFailed(var suggestion, let error, _):
            suggestion.reason = suggestion.reason + "\n\(error)"
            recentEnacted = await storage.appendAndModify([suggestion], to: OpenAPS.Upload.recentEnacted, uniqBy: \.timestamp) {
                $0.filter { ($0.timestamp ?? .distantPast) >= hoursAgo30 }
            }

            recentSuggested = await storage.retrieve(OpenAPS.Upload.recentSuggested, as: [Suggestion].self) ?? []
        case let .suggested(suggestion, _):
            recentSuggested = await storage.appendAndModify(
                [suggestion],
                to: OpenAPS.Upload.recentSuggested,
                uniqBy: \.timestamp
            ) {
                $0.filter { ($0.timestamp ?? .distantPast) >= hoursAgo30 }
            }

            recentEnacted = await storage.retrieve(OpenAPS.Upload.recentEnacted, as: [Suggestion].self) ?? []
        case .failed:
            recentEnacted = await storage.retrieve(OpenAPS.Upload.recentEnacted, as: [Suggestion].self) ?? []
            recentSuggested = await storage.retrieve(OpenAPS.Upload.recentSuggested, as: [Suggestion].self) ?? []
        }

        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }

        var uploadedSuggested: Set<Date> = Set([])

        for suggested in recentSuggested {
            guard let timestamp = suggested.timestamp else { continue }
            let status = NightscoutStatus(
                device: NigtscoutTreatment.local,
                openaps: OpenAPSStatus(
                    iob: nil,
                    suggested: suggested,
                    enacted: nil,
                    version: iapsVersion
                ),
                pump: nil,
                uploader: nil,
                createdAt: timestamp
            )
            do {
                try await nightscout.uploadStatus(status)
                debug(.nightscout, "suggestion uploaded")
                uploadedSuggested.insert(timestamp)
            } catch {
                debug(.nightscout, error.localizedDescription)
            }
        }

        var uploadedEnacted: Set<Date> = Set([])

        for enacted in recentEnacted {
            guard let timestamp = enacted.timestamp else { continue }

            let status = NightscoutStatus(
                device: NigtscoutTreatment.local,
                openaps: OpenAPSStatus(
                    iob: nil,
                    suggested: enacted,
                    // Nightscout requires both enacted and suggested fields to be specified in order to show predictions on graph.
                    enacted: enacted,
                    version: iapsVersion
                ),
                pump: nil,
                uploader: nil,
                createdAt: timestamp
            )
            do {
                try await nightscout.uploadStatus(status)
                debug(.nightscout, "enacted suggestion uploaded")
                uploadedEnacted.insert(timestamp)
            } catch {
                debug(.nightscout, error.localizedDescription)
            }
        }

        if uploadedSuggested.isNotEmpty {
            let uploadedSuggestedSnapshot = uploadedSuggested
            await storage.modify(file: OpenAPS.Upload.recentSuggested, as: Suggestion.self) {
                $0.filter { !uploadedSuggestedSnapshot.contains($0.timestamp ?? .distantPast) }
            }
        }

        if uploadedEnacted.isNotEmpty {
            let uploadedEnactedSnapshot = uploadedEnacted
            await storage.modify(file: OpenAPS.Upload.recentEnacted, as: Suggestion.self) {
                $0.filter { !uploadedEnactedSnapshot.contains($0.timestamp ?? .distantPast) }
            }
        }
    }

    private func uploadIOB(_ iob: [IOBEntry]) async {
        guard let iob = iob.first else {
            return
        }

        let settings = appCoordinator.settings.value

        guard let nightscout = nightscoutAPI, settings.isUploadEnabled else {
            return
        }

        let status = NightscoutStatus(
            device: NigtscoutTreatment.local,
            openaps: OpenAPSStatus(
                iob: iob,
                suggested: nil,
                enacted: nil,
                version: iapsVersion
            ),
            pump: nil,
            uploader: nil,
            createdAt: iob.time ?? Date.now
        )

        do {
            try await nightscout.uploadStatus(status)
            debug(.nightscout, "iob uploaded")
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
    }

    private func uploadPodAge(podActivatedAt: Date) async {
        guard podActivatedAt != self.lastUploadedPodAge else {
            return
        }
        let uploadedPodAge = await storage.retrieve(OpenAPS.Nightscout.uploadedPodAge, as: [NigtscoutTreatment].self) ?? []
        guard uploadedPodAge.last?.createdAt != podActivatedAt else {
            self.lastUploadedPodAge = podActivatedAt
            return
        }
        let siteTreatment = NigtscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .nsSiteChange,
            createdAt: podActivatedAt,
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
        if await uploadTreatments(
            storedEvents: [siteTreatment],
            fileToSave: OpenAPS.Nightscout.uploadedPodAge,
            uploadedRetention: .days(15) // keep 15 days in the .uploadedPodAge file to avoid unnecessary re-uploads of the same pod age
        ) {
            self.lastUploadedPodAge = podActivatedAt
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
            saveToUploaded: false, // do not update the "already uploaded glucose" file
            settings: settings
        )
    }

    private func pumpHistoryUpdated(_ pumpHistory: [PumpHistoryEvent]) async {
        await uploadTreatments(
            storedEvents: convertPumpHistoryToNightscout(events: pumpHistory),
            fileToSave: OpenAPS.Nightscout.uploadedPumphistory,
            uploadedRetention: .hours(30)
        )
    }

    private func pumpHistoryDeleted(_ deleted: [PumpHistoryEvent]) async {
        guard deleted.isNotEmpty || deletedPumpHistoryPending else { return }

        let allDeleted = await deleteTreatments(
            deletedTreatments: convertPumpHistoryToNightscout(events: deleted),
            fileToSave: OpenAPS.Nightscout.pumpHistoryToDelete,
            retention: .hours(30)
        )
        deletedPumpHistoryPending = !allDeleted
    }

    private func glucoseHistoryUpdated(_ bloodGlucose: [BloodGlucose]) async {
        let settings = appCoordinator.settings.value
        guard nightscoutAPI != nil, settings.isUploadEnabled, bloodGlucose.isNotEmpty, isNetworkReachable,
              appCoordinator.cgmStatus.value?.shouldUploadGlucose == true
        else {
            return
        }

        let uploaded = await storage.retrieve(OpenAPS.Nightscout.uploadedGlucose, as: [BloodGlucose].self) ?? []

        let notUploaded = Array(Set(bloodGlucose).subtracting(Set(uploaded)))

        await uploadGlucose(
            upload: notUploaded,
            saveToUploaded: true,
            settings: settings
        ).drain()
    }

    private func glucoseDeleted(_ deleted: [BloodGlucose]) async {
        let deletedManualGlucose = deleted.filter { $0.type == GlucoseType.manual.rawValue }

        guard deletedManualGlucose.isNotEmpty || deletedGlucosePending else { return }

        let hoursAgo30 = Date.now.removingTimeInterval(.hours(30))
        let glucoseToDelete = await storage.appendAndModify(
            deletedManualGlucose,
            to: OpenAPS.Nightscout.glucoseToDelete,
            uniqBy: \.dateString
        ) {
            $0.filter { $0.dateString >= hoursAgo30 }
        }

        let allDeleted = await deleteManualGlucose(glucoseToDelete)
        deletedGlucosePending = !allDeleted
    }

    private func deleteManualGlucose(_ glucoseToDelete: [BloodGlucose]) async -> Bool {
        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled, glucoseToDelete.isNotEmpty, isNetworkReachable else {
            return glucoseToDelete.isEmpty
        }
        var deletedFromNightscout: [BloodGlucose] = []
        for deletedGlucose in glucoseToDelete {
            do {
                try await nightscout.deleteManualGlucose(at: deletedGlucose.dateString)
                deletedFromNightscout.append(deletedGlucose)
                debug(
                    .nightscout,
                    "Manual Glucose entry deleted: \(deletedGlucose.dateString.formatted(.iso8601WithFractionalSeconds))"
                )
            } catch {
                debug(
                    .nightscout,
                    "failed to delete manual glucose from nightscout: \(deletedGlucose.dateString.formatted(.iso8601WithFractionalSeconds)) - \(error.localizedDescription)"
                )
                break
            }
        }

        let deletedFromNightscoutDates = Set(deletedFromNightscout.map(\.dateString))
        let (remainingToDelete, _) = await storage.delete(file: OpenAPS.Nightscout.glucoseToDelete, as: BloodGlucose.self) {
            deletedFromNightscoutDates.contains($0.dateString)
        }
        debug(.nightscout, "manual glucose deleted from nightscout: \(deletedFromNightscout.count)/\(glucoseToDelete.count)")
        return remainingToDelete.isEmpty
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
        if await uploadTreatments(
            storedEvents: cgmStateToUpload,
            fileToSave: OpenAPS.Nightscout.uploadedCGMState,
            uploadedRetention: .days(40) // we keep 30 days in .cgmState file, so we should keep >30 days in .uploadedCGMState
        ) {
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
                createdAt: date.truncatedToSecond,
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
        await uploadTreatments(
            storedEvents: convertCarbHistoryToNightscout(events: carbHistory),
            fileToSave: OpenAPS.Nightscout.uploadedCarbs,
            uploadedRetention: .hours(30)
        )
    }

    private func carbsDeleted(_ deleted: [CarbsEntry]) async {
        guard deleted.isNotEmpty || deletedCarbsPending else { return }

        let allDeleted = await deleteTreatments(
            deletedTreatments: convertCarbHistoryToNightscout(events: deleted),
            fileToSave: OpenAPS.Nightscout.carbsToDelete,
            retention: .hours(30)
        )
        deletedCarbsPending = !allDeleted
    }

    private func tempTargetsUpdated(_ tempTargets: [TempTarget]) async {
        await uploadTreatments(
            storedEvents: convertTempTargetsToNightscout(events: tempTargets),
            fileToSave: OpenAPS.Nightscout.uploadedTempTargets,
            uploadedRetention: .hours(30)
        )
    }

    /// upload `glucose` to nightscout, upon success - if saveToUploaded=true, append uploaded glucose to storage so we don't upload any of it next time
    private func uploadGlucose(
        upload glucose: [BloodGlucose],
        saveToUploaded: Bool,
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
                    if saveToUploaded {
                        _ = await storage
                            .modify(file: OpenAPS.Nightscout.uploadedGlucose, as: BloodGlucose.self) { previousUploaded in
                                let hoursAgo25 = Date.now.removingTimeInterval(.hours(25))
                                return (previousUploaded + glucose)
                                    .uniqued(on: \.dateString)
                                    .filter { $0.dateString > hoursAgo25 }
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

    /// * read the snapshot of previously uploaded treatments from the file
    /// * detect new treatments in the current local data and upload them
    /// * update the 'previously uploaded' file, removing entries older than `now - uploadedRetention`
    @discardableResult private func uploadTreatments(
        storedEvents treatments: [NigtscoutTreatment],
        fileToSave: String,
        uploadedRetention: TimeInterval
    ) async -> Bool {
        guard let nightscout = nightscoutAPI, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable else {
            return false
        }

        guard treatments.isNotEmpty else {
            return true
        }

        let previouslyUploaded = await storage.retrieve(fileToSave, as: [NigtscoutTreatment].self) ?? []
        let previouslyUploadedKeys = Set(previouslyUploaded.map(\.identity))

        let treatmentsToUpload = treatments.filter { !previouslyUploadedKeys.contains($0.identity) }
            .sorted { $0.createdAt > $1.createdAt }

        do {
            for chunk in treatmentsToUpload.chunks(ofCount: 100) {
                try await nightscout.uploadTreatments(Array(chunk))
            }

            let eventTypes = treatments.map(\.eventType).uniqued().map(\.rawValue).joined(separator: ", ")
            debug(.nightscout, "treatments uploaded (\(eventTypes)): \(treatmentsToUpload.count)")

            let storedKeys = Set(treatments.map(\.identity))
            let cutoff = Date().removingTimeInterval(uploadedRetention)
            await storage.modify(file: fileToSave, as: NigtscoutTreatment.self) { previouslyUploaded in
                (previouslyUploaded + treatmentsToUpload)
                    // only store events not older than uploadedRetention, but keep everything that is present in storage to avoid re-uploads
                    .filter { $0.createdAt >= cutoff || storedKeys.contains($0.identity) }
                    // newest -> oldest
                    .sorted { $0.createdAt > $1.createdAt }
            }
            return true
        } catch {
            debug(.nightscout, error.localizedDescription)
        }
        return false
    }

    private func deleteTreatments(
        deletedTreatments deleted: [NigtscoutTreatment],
        fileToSave: String,
        retention: TimeInterval
    ) async -> Bool {
        let cutoff = Date.now.removingTimeInterval(retention)

        let treatmentsToDelete = await storage.appendAndModify(deleted, to: fileToSave, uniqBy: \.identity) {
            $0.filter { $0.createdAt >= cutoff }.sorted { $0.createdAt > $1.createdAt }
        }

        let settings = appCoordinator.settings.value
        guard let nightscout = nightscoutAPI, settings.isUploadEnabled, treatmentsToDelete.isNotEmpty, isNetworkReachable else {
            return treatmentsToDelete.isEmpty
        }

        let eventTypes = treatmentsToDelete.map(\.eventType).uniqued().map(\.rawValue)
            .joined(separator: ", ")

        var deletedFromNS: [NigtscoutTreatment] = []
        for treatment in treatmentsToDelete {
            do {
                try await nightscout.deleteTreatment(treatment)
                deletedFromNS.append(treatment)
                debug(
                    .nightscout,
                    "deleted \(treatment.eventType) treatment from NS: \(treatment.createdAt.formatted(.iso8601WithFractionalSeconds))"
                )
            } catch {
                debug(
                    .nightscout,
                    "failed to delete \(treatment.eventType) treatment from NS: \(treatment.createdAt.formatted(.iso8601WithFractionalSeconds))"
                )
                break
            }
        }

        debug(.nightscout, "treatments delete - \(eventTypes): deleted: \(deletedFromNS.count)")

        let deletedFromNSKeys = Set(deletedFromNS.map(\.identity))
        let notDeleted = await storage.modify(file: fileToSave, as: NigtscoutTreatment.self) {
            $0.filter { !deletedFromNSKeys.contains($0.identity) }
        }
        return notDeleted.isEmpty
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
                    createdAt: event.timestamp.truncatedToSecond,
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
                guard var last = result.popLast() else { break }
                if last.eventType == .nsTempBasal,
                   last.createdAt == event.timestamp.truncatedToSecond
                {
                    last.duration = event.durationMin
                    last.rawDuration = event
                }
                result.append(last)
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
                    createdAt: event.timestamp.truncatedToSecond,
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
                    createdAt: event.timestamp.truncatedToSecond,
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
                    createdAt: event.timestamp.truncatedToSecond,
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
                    createdAt: event.timestamp.truncatedToSecond,
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
                    createdAt: event.timestamp.truncatedToSecond,
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

        return (
            bolusesAndCarbs +
            temps.filter { $0.duration != nil } +
            misc
        ).sorted { $0.createdAt > $1.createdAt }
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
                createdAt: $0.actualDate?.truncatedToSecond ?? .distantPast,
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
                createdAt: $0.createdAt.truncatedToSecond,
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
