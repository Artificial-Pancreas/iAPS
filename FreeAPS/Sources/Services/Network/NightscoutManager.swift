import Foundation
import NightscoutKit
import Swinject

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

    private var pumpHistorySync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>!
    private var glucoseSync: DataSynchronizer<BloodGlucose, NightscoutGlucoseSink>!
    private var carbsSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>!
    private var tempTargetsSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>!
    private var podAgeSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>!
    private var cgmStateSync: DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink>!

    private var deviceStatusUploader: NightscoutDeviceStatusUploader!

    private let overrideStorage = OverrideStorage()

    private var ping: TimeInterval?

    private var lastSeenCgmStart: Date?

    let lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var nightscoutAPI: NightscoutAPI?

    init(
        keychain: Keychain,
        appCoordinator: AppCoordinator,
        glucoseStorage: GlucoseStorage,
        tempTargetsStorage: TempTargetsStorage,
        carbsStorage: CarbsStorage,
        storage: FileStorage,
        announcementsStorage: AnnouncementsStorage,
        settingsManager: SettingsManager,
        reachabilityManager: ReachabilityManager
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
    }

    // this is called at the start of the app
    func start() async {
        reloadNightscoutConfiguration()

        pumpHistorySync = treatmentSync(
            name: "ns.treatments",
            snapshotFile: OpenAPS.Nightscout.uploadedPumphistory,
            retention: .hours(24),
            deletionWindow: .hours(8)
        )

        glucoseSync = DataSynchronizer(
            name: "ns.glucose",
            sink: NightscoutGlucoseSink(apiProvider: { [self] in await nightscoutAPI }),
            storage: storage,
            snapshotFile: OpenAPS.Nightscout.uploadedGlucose,
            retention: .hours(24),
            deletionWindow: .hours(8),
            category: .nightscout
        )

        carbsSync = treatmentSync(
            name: "ns.carbs",
            snapshotFile: OpenAPS.Nightscout.uploadedCarbs,
            retention: .hours(24),
            deletionWindow: .hours(8)
        )

        tempTargetsSync = treatmentSync(
            name: "ns.tempTargets",
            snapshotFile: OpenAPS.Nightscout.uploadedTempTargets,
            retention: .hours(24),
            deletionWindow: 0 // append-only
        )

        podAgeSync = treatmentSync(
            name: "ns.podAge",
            snapshotFile: OpenAPS.Nightscout.uploadedPodAge,
            retention: .days(15),
            deletionWindow: 0 // append-only
        )

        cgmStateSync = treatmentSync(
            name: "ns.cgmState",
            snapshotFile: OpenAPS.Nightscout.uploadedCGMState,
            retention: .days(40),
            deletionWindow: 0 // append-only
        )

        deviceStatusUploader = NightscoutDeviceStatusUploader(
            apiProvider: { [self] in await nightscoutAPI },
            isUploadEnabled: { [appCoordinator] in appCoordinator.settings.value.isUploadEnabled },
            storage: storage
        )

        observe(appCoordinator.nightscoutConfigChanged) { me, _ in
            await me.reloadNightscoutConfiguration()
        }
        observe(appCoordinator.carbHistory) { me, carbHistory in
            await withBackgroundTask("nightscout upload - carb history") {
                await me.carbHistoryUpdated(carbHistory)
            }
        }

        observe(appCoordinator.tempTargets) { me, tempTargets in
            await withBackgroundTask("nightscout upload - temp targets") {
                await me.tempTargetsUpdated(tempTargets)
            }
        }

        observe(appCoordinator.glucoseHistory) { me, bloodGlucose in
            await withBackgroundTask("nightscout upload - blood glucose") {
                await me.glucoseHistoryUpdated(bloodGlucose)
            }
        }

        observe(appCoordinator.pumpHistory) { me, pumpHistory in
            await withBackgroundTask("nightscout upload - pump history") {
                await me.pumpHistoryUpdated(pumpHistory)
            }
        }

        observe(appCoordinator.cgmStatus) { me, cgmStatus in
            if let cgmStatus {
                await withBackgroundTask("nightscout upload - cgm status") {
                    await me.cgmStatusUpdated(cgmStatus)
                }
            }
        }

        observe(appCoordinator.pumpStatus) { me, pumpStatus in
            if let pumpStatus {
                await withBackgroundTask("nightscout upload - pump status") {
                    await me.deviceStatusUploader.pumpStatusUpdated(pumpStatus)
                }
            }
        }
        observe(appCoordinator.pumpInfo.map(\.?.podActivatedAt)) { me, podActivatedAt in
            if let podActivatedAt {
                await withBackgroundTask("nightscout upload - pod activation") {
                    await me.uploadPodAge(podActivatedAt: podActivatedAt)
                }
            }
        }

        observe(appCoordinator.loopCompleted) { me, outcome in
            await withBackgroundTask("nightscout upload - device status") {
                await me.deviceStatusUploader.loopCompleted(outcome)
                await me.retryPodAgeIfNeeded()
            }
        }

        observe(appCoordinator.iobTicks.dropFirst()) { me, iobTicks in
            if let iobTicks {
                await withBackgroundTask("nightscout upload - iob") {
                    await me.deviceStatusUploader.uploadIOB(iobTicks)
                }
            }
        }
    }

    private func treatmentSync(
        name: String,
        snapshotFile: String,
        retention: TimeInterval,
        deletionWindow: TimeInterval
    ) -> DataSynchronizer<NigtscoutTreatment, NightscoutTreatmentSink> {
        DataSynchronizer(
            name: name,
            sink: NightscoutTreatmentSink(apiProvider: { [self] in await nightscoutAPI }),
            storage: storage,
            snapshotFile: snapshotFile,
            retention: retention,
            deletionWindow: deletionWindow,
            category: .nightscout
        )
    }

    private func makeNightscoutAPI() -> NightscoutAPI? {
        guard let urlString = keychain.getValue(String.self, forKey: NightscoutConfig.Config.urlKey),
              let url = URL(string: urlString),
              let secret = keychain.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
        else {
            return nil
        }
        return NightscoutAPI(url: url, secret: secret)
    }

    private func reloadNightscoutConfiguration() {
        nightscoutAPI = makeNightscoutAPI()
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

    private func podSiteTreatment(podActivatedAt: Date) -> NigtscoutTreatment {
        NigtscoutTreatment(
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
    }

    private func uploadPodAge(podActivatedAt: Date) async {
        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable else {
            await podAgeSync.markPending()
            return
        }
        let siteTreatment = podSiteTreatment(podActivatedAt: podActivatedAt)
        await podAgeSync.reconcile { [siteTreatment] }
    }

    private func retryPodAgeIfNeeded() async {
        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable,
              let podActivatedAt = appCoordinator.pumpInfo.value?.podActivatedAt
        else {
            return
        }
        let siteTreatment = podSiteTreatment(podActivatedAt: podActivatedAt)
        await podAgeSync.reconcile(trigger: .retry) { [siteTreatment] }
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
        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable else { return }
        let treatments = convertPumpHistoryToNightscout(events: pumpHistory)
        await pumpHistorySync.reconcile { treatments }
    }

    private func glucoseHistoryUpdated(_ bloodGlucose: [BloodGlucose]) async {
        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable,
              appCoordinator.cgmStatus.value?.shouldUploadGlucose == true
        else {
            return
        }
        await glucoseSync.reconcile { bloodGlucose }
    }

    private func cgmStatusUpdated(_ cgmStatus: CgmDisplayStatus) async {
        // sensor-change log
        var recorded: [NigtscoutTreatment]?
        if let sessionStartDate = cgmStatus.sessionStartDate,
           abs(sessionStartDate.timeIntervalSince(lastSeenCgmStart ?? .distantPast)) > 60
        {
            self.lastSeenCgmStart = sessionStartDate
            recorded = await recordSensorStartIfNeeded(sessionStartDate)
        }

        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled,
              cgmStatus.shouldUploadGlucose, isNetworkReachable
        else {
            if recorded != nil {
                await cgmStateSync.markPending()
            }
            return
        }

        if let recorded {
            await cgmStateSync.reconcile { recorded }
        } else {
            // retry previous uploads if needed
            await cgmStateSync.reconcile(trigger: .retry) { [self] in await readCgmState() }
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

    func uploadOverride(_ profile: String, _ duration: Double, _ date: Date) async {
        await deviceStatusUploader.uploadOverride(profile, duration, date)
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

    private func carbHistoryUpdated(_ carbHistory: [CarbsEntry]) async {
        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable else { return }
        let treatments = convertCarbHistoryToNightscout(events: carbHistory)
        await carbsSync.reconcile { treatments }
    }

    private func tempTargetsUpdated(_ tempTargets: [TempTarget]) async {
        guard nightscoutAPI != nil, appCoordinator.settings.value.isUploadEnabled, isNetworkReachable else { return }
        let treatments = convertTempTargetsToNightscout(events: tempTargets)
        await tempTargetsSync.reconcile { treatments }
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
                    $0.carbs > 0 && $0.isFPU != true }
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
                fat: $0.fat,
                protein: $0.protein,
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
                duration: $0.duration,
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
