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
    private let tempTargetsStorage: TempTargetsStorage
    private let carbsStorage: CarbsStorage
    private let storage: FileStorage
    private let announcementsStorage: AnnouncementsStorage
    private let reachabilityManager: ReachabilityManager

    private var dataSync: NightscoutDataSync!
    private var deviceStatusUploader: NightscoutDeviceStatusUploader!

    private let overrideStorage = OverrideStorage()

    private var ping: TimeInterval?

    let lifetime = Lifetime()

    private var isNetworkReachable: Bool {
        reachabilityManager.isReachable
    }

    private var nightscoutAPI: NightscoutAPI?

    init(
        keychain: Keychain,
        appCoordinator: AppCoordinator,
        tempTargetsStorage: TempTargetsStorage,
        carbsStorage: CarbsStorage,
        storage: FileStorage,
        announcementsStorage: AnnouncementsStorage,
        reachabilityManager: ReachabilityManager
    ) {
        self.keychain = keychain
        self.appCoordinator = appCoordinator
        self.tempTargetsStorage = tempTargetsStorage
        self.carbsStorage = carbsStorage
        self.storage = storage
        self.announcementsStorage = announcementsStorage
        self.reachabilityManager = reachabilityManager
    }

    // this is called at the start of the app
    func start() async {
        reloadNightscoutConfiguration()

        dataSync = NightscoutDataSync(
            apiProvider: { [self] in await nightscoutAPI },
            appCoordinator: appCoordinator,
            reachabilityManager: reachabilityManager,
            storage: storage
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
                await me.dataSync.carbHistoryUpdated(carbHistory)
            }
        }

        observe(appCoordinator.tempTargets) { me, tempTargets in
            await withBackgroundTask("nightscout upload - temp targets") {
                await me.dataSync.tempTargetsUpdated(tempTargets)
            }
        }

        observe(appCoordinator.glucoseHistory) { me, bloodGlucose in
            await withBackgroundTask("nightscout upload - blood glucose") {
                await me.dataSync.glucoseHistoryUpdated(bloodGlucose)
            }
        }

        observe(appCoordinator.pumpHistory) { me, pumpHistory in
            await withBackgroundTask("nightscout upload - pump history") {
                await me.dataSync.pumpHistoryUpdated(pumpHistory)
            }
        }

        observe(appCoordinator.cgmStatus) { me, cgmStatus in
            if let cgmStatus {
                await withBackgroundTask("nightscout upload - cgm status") {
                    await me.dataSync.cgmStatusUpdated(cgmStatus)
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
                    await me.dataSync.uploadPodAge(podActivatedAt: podActivatedAt)
                }
            }
        }

        observe(appCoordinator.loopCompleted) { me, outcome in
            await withBackgroundTask("nightscout upload - device status") {
                await me.deviceStatusUploader.loopCompleted(outcome)
                await me.dataSync.retryPodAgeIfNeeded()
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
}

private extension AsyncSequence {
    func drain() async rethrows {
        for try await _ in self {}
    }
}
