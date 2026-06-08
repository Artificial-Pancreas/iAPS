import AsyncAlgorithms
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject

protocol APSManager: Sendable {
    func autotune() async -> Autotune?
    func enactBolus(amount: Double, isSMB: Bool) async
//    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
//    var pumpName: CurrentValueSubject<String, Never> { get }
//    var lastLoopDate: Date { get }

//    var bolusProgress: CurrentValueSubject<Decimal?, Never> { get }
//    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
//    var isManualTempBasal: Bool { get }
//    var bolusAmount: CurrentValueSubject<Decimal?, Never> { get }
//    var temporaryData: TemporaryData { get set }
//    var concentration: (concentration: Double, increment: Double) { get }
    func enactTempBasal(rate: Double, duration: TimeInterval) async
    func makeProfiles() async -> Bool
    func determineBasal(
        temporaryCarbs: CarbsEntry?
    ) async -> Suggestion?
//    func determineBasalSync()
    func iobSync() async -> Decimal?
    func roundBolus(amount: Decimal) async -> Decimal
//    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus() async
    func enactAnnouncement(_ announcement: Announcement) async
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case bolusInProgress(message: String)
    case glucoseError(message: String)
    case apsError(message: String)
    case deviceSyncError(message: String)
    case manualBasalTemp(message: String)
    case activeBolusViewBolus
    case activeBolusViewBasal
    case activeBolusViewBasalandBolus

    var errorDescription: String? {
        switch self {
        case let .pumpError(error):
            return "Pump error: \(error.localizedDescription)"
        case let .invalidPumpState(message):
            return "Error: Invalid Pump State: \(message)"
        case let .bolusInProgress(message):
            return "\(NSLocalizedString("Pump is Busy.", comment: "Pump Error")) \(NSLocalizedString(message, comment: "Pump Error Message"))"
        case let .glucoseError(message):
            return "Error: Invalid glucose: \(message)"
        case let .apsError(message):
            return "APS error: \(message)"
        case let .deviceSyncError(message):
            return "Sync error: \(message)"
        case let .manualBasalTemp(message):
            return "Manual Basal Temp : \(message)"
        case .activeBolusViewBolus:
            return "Suggested SMB not enacted while in Bolus View"
        case .activeBolusViewBasal:
            return "Suggested Temp Basal (when > 0) not enacted while in Bolus View"
        case .activeBolusViewBasalandBolus:
            return "Suggested Temp Basal (when > 0) and SMB not enacted while in Bolus View"
        }
    }
}

actor BaseAPSManager: APSManager, LifetimeOwner, AppService {
    private let processQueue = DispatchQueue(label: "BaseAPSManager.processQueue")
    private let appCoordinator: AppCoordinator
    private let storage: FileStorage
    private let pumpHistoryStorage: PumpHistoryStorage
    private let glucoseStorage: GlucoseStorage
    private let tempTargetsStorage: TempTargetsStorage
    private let carbsStorage: CarbsStorage
    private let announcementsStorage: AnnouncementsStorage
    private let deviceDataManager: DeviceDataManager
    private let nightscout: NightscoutManager
    private let settingsManager: SettingsManager
    private let openAPS: OpenAPS

    private let overrideStorage = OverrideStorage()

    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
    @Persisted(key: "lastStartLoopDate") private var lastStartLoopDate: Date = .distantPast
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast

    private let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
    private let coreDataStorage = CoreDataStorage()

    let lifetime = Lifetime()

    private var wasManualTempBasal = false

    private var concentration: (concentration: Double, increment: Double) {
        coreDataStorage.insulinConcentration()
    }

    private var override: Override? {
        guard let last = overrideStorage.fetchLatestOverride().first, last.enabled else { return nil }
        return last
    }

    init(
        appCoordinator: AppCoordinator,
        storage: FileStorage,
        pumpHistoryStorage: PumpHistoryStorage,
        glucoseStorage: GlucoseStorage,
        tempTargetsStorage: TempTargetsStorage,
        carbsStorage: CarbsStorage,
        announcementsStorage: AnnouncementsStorage,
        deviceDataManager: DeviceDataManager,
        nightscout: NightscoutManager,
        settingsManager: SettingsManager,
        openAPS: OpenAPS
    ) {
        self.appCoordinator = appCoordinator
        self.storage = storage
        self.pumpHistoryStorage = pumpHistoryStorage
        self.glucoseStorage = glucoseStorage
        self.tempTargetsStorage = tempTargetsStorage
        self.carbsStorage = carbsStorage
        self.announcementsStorage = announcementsStorage
        self.deviceDataManager = deviceDataManager
        self.nightscout = nightscout
        self.settingsManager = settingsManager
        self.openAPS = openAPS
    }

    // this is called at the app start
    func start() async {
        // because of backfill, the recommendation might trigger before the backfill is received
        // debounce for 1 second to give the CGM a chance to send in the backfill
        observe(
            appCoordinator.recommendsLoop.sendableValues.debounce(for: .seconds(1))
        ) { me, _ in
            await me.loop()
        }

        observe(appCoordinator.deviceErrors) { me, error in
            await me.processError(APSError.pumpError(error))
        }

        observe(appCoordinator.bolusInProgress.dropFirst()) { me, bolusing in
            if bolusing {
                await me.createBolusReporter()
            } else {
                await me.clearBolusReporter()
            }
        }

        // manage a manual Temp Basal from OmniPod - Force loop() after stop a temp basal or finished
        observe(appCoordinator.manualTempBasal) { me, manualBasal in
            await me.manualTempBasalUpdated(manualBasal)
        }

        appCoordinator.setLastLoopDate(lastLoopDate)
    }

    private func manualTempBasalUpdated(_ manualBasal: Bool) async {
        if manualBasal {
            wasManualTempBasal = true
        } else if wasManualTempBasal {
            // manual temp basal turned off -> loop
            wasManualTempBasal = false
            await loop()
        }
    }

    // Loop entry point
    private func loop() async {
        let settings = await settingsManager.settings
        // check the last start of looping is more the loopInterval but the previous loop was completed
        if lastLoopDate > lastStartLoopDate {
            let loopInterval = settings.allowOneMinuteLoop ? Config.loopIntervalOneMinute : Config.loopIntervalFiveMinutes
            guard Date().timeIntervalSince(lastStartLoopDate) >= loopInterval else {
                debug(.apsManager, "too close to do a loop : \(lastStartLoopDate)")
                return
            }
        }

        guard !appCoordinator.isLooping.value else {
            warning(.apsManager, "Loop already in progress. Skip recommendation.")
            return
        }

        // start background time extension
        let backgroundTaskIdBox = TaskIDBox()
        let backgroundTimeRemaining = await MainActor.run { () -> TimeInterval in
            backgroundTaskIdBox.id = UIApplication.shared.beginBackgroundTask(withName: "Loop starting") {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdBox.id)
            }
            return UIApplication.shared.backgroundTimeRemaining
        }
//        backGroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Loop starting") { [self] in
//            guard let backgroundTask = backGroundTaskID else { return }
//            UIApplication.shared.endBackgroundTask(backgroundTask)
//            self.backGroundTaskID = .invalid
//        }

        debug(.apsManager, "Starting loop, background time remaining: \(backgroundTimeRemaining.rounded())")

        let lastStartLoopDate = Date()
        self.lastStartLoopDate = lastStartLoopDate

        let interval: Double? = await coredataContext.perform {
            let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sortStats = NSSortDescriptor(key: "end", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            let previousLoop = (try? self.coredataContext.fetch(requestStats)) ?? []

            if (previousLoop.first?.end ?? .distantFuture) < lastStartLoopDate {
                return Self.roundDouble((lastStartLoopDate - (previousLoop.first?.end ?? Date())).timeInterval / 60, 1)
            }
            return nil
        }

        let loopStatRecord = LoopStats(
            start: lastStartLoopDate,
            loopStatus: "Starting",
            interval: interval
        )

        appCoordinator.setIsLooping(true)

        do {
            guard let suggestion = await determineBasal(temporaryCarbs: nil) else {
                throw APSError.apsError(message: "Determine basal failed")
            }

            // Open loop completed
            if settings.closedLoop {
                try await self.enactSuggested(suggested: suggestion)
            }

            await self.loopCompleted(loopStatRecord: loopStatRecord)
            await self.nightscout.uploadStatus()
        } catch {
            await self.loopCompleted(loopStatRecord: loopStatRecord, error: error)
        }

        appCoordinator.setIsLooping(false)

        // TODO: is this a good idea?
        // give background tasks a chance to finish?
        try? await Task.sleep(for: .seconds(10))
        // end of the BG tasks
        await MainActor.run {
            if backgroundTaskIdBox.id != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdBox.id)
            }
        }
    }

    // Loop exit point
    private func loopCompleted(loopStatRecord: LoopStats, error: Error? = nil) async {
        var loopStatRecord = loopStatRecord
        loopStatRecord.end = Date()
        loopStatRecord.duration = Self.roundDouble(
            (loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2
        )
        loopStatRecord.loopStatus = error?.localizedDescription ?? "Success"

        if let apsError = error {
            warning(.apsManager, "Loop failed with error: \(apsError.localizedDescription)")
//            TODO: [loopkit] was this necessary here? the task is ended at the end of this method

//            if let backgroundTask = backGroundTaskID {
//                UIApplication.shared.endBackgroundTask(backgroundTask)
//                backGroundTaskID = .invalid
//            }
            await processError(apsError)

        } else {
            debug(.apsManager, "Loop succeeded")
            lastLoopDate = Date()
            appCoordinator.setLastLoopDate(lastLoopDate)
            appCoordinator.setLastLoopError(nil)
        }

        persistLoopStats(loopStatRecord: loopStatRecord, error: error)

        let settings = await settingsManager.settings

        if settings.closedLoop {
            await reportEnacted(received: error == nil)
        }
    }

    private func verifyStatus() async -> Error? {
        guard let status = appCoordinator.pumpStatus.value else {
            return APSError.invalidPumpState(message: "Pump not set")
        }

        if status.isBolusing {
            return APSError.bolusInProgress(
                message: "Can't enact the new loop cycle recommendation, because a Bolus is in progress. Wait for next loop cycle"
            )
        }

        if status.isSuspended {
            return APSError.invalidPumpState(message: "Pump suspended")
        }

        // TODO: do we need this check here? pump will return an error, and reservoir might be inaccurate...
//        let reservoir = await storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
//        guard reservoir >= 0 else {
//            return APSError.invalidPumpState(message: "Reservoir is empty")
//        }

        return nil
    }

    private func autosens() async -> Bool {
        guard let autosens = await storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self),
              (autosens.timestamp ?? .distantPast).addingTimeInterval(30.minutes.timeInterval) > Date()
        else {
            return await openAPS.autosense() != nil
        }

        return false
    }

    func determineBasal(
        temporaryCarbs: CarbsEntry?
    ) async -> Suggestion? {
        debug(.apsManager, "Start determine basal")
        guard let glucose = await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self), glucose.isNotEmpty else {
            debug(.apsManager, "Not enough glucose data")
            await processError(APSError.glucoseError(message: "Not enough glucose data"))
            return nil
        }

        let lastGlucoseDate = await glucoseStorage.latestDate() ?? .distantPast
        guard lastGlucoseDate > Date().addingTimeInterval(-12.minutes.timeInterval) else {
            debug(.apsManager, "Glucose data is stale")
            await processError(APSError.glucoseError(message: "Glucose data is stale"))
            return nil
        }

        let settings = await settingsManager.settings
        let preferences = await settingsManager.preferences

        let now = Date()
        let temp = await currentTemp(date: now)
//        let temporary = temporaryData
//        temporaryData.forBolusView.carbs = 0

        guard let pumpStatus = appCoordinator.pumpStatus.value else {
            await processError(APSError.invalidPumpState(message: "Pump not set"))
            return nil
        }

        if temp.duration == 0,
           settings.closedLoop,
           preferences.unsuspendIfNoTemp,
           pumpStatus.isSuspended
        {
            do {
                try await deviceDataManager.resumeDelivery()
            } catch {
                debug(.apsManager, "failed to resume delivery: \(error.localizedDescription)")
                return nil
            }
        }

        _ = await makeProfiles()
        _ = await autosens()
        _ = await dailyAutotune()
        let override = self.override
        let suggestion = await openAPS.determineBasal(
            currentTemp: temp,
            clock: now,
            temporaryCarbs: temporaryCarbs,
            override: override
        )
        if let suggestion {
            appCoordinator.sendSuggestion(suggestion)
        }
        return suggestion
    }

    func iobSync() async -> Decimal? {
        let sync = await openAPS.iobSync()
        guard let iobEntries = IOBTick0.parseArrayFromJSON(from: sync) else { return nil }

        return coreDataStorage.saveInsulinData(iobEntries: iobEntries)
    }

//    // TODO: this needs to be deleted
//    func determineBasalSync() {
//        Task {
//            await determineBasal(temporaryCarbs: nil)
//        }
//    }

    func makeProfiles() async -> Bool {
        let settings = await settingsManager.settings
        let tunedProfile = await openAPS.makeProfiles(useAutotune: settings.useAutotune, settings: settings)

        if let basalProfile = tunedProfile?.basalProfile {
            appCoordinator.sendBasalProfile(basalProfile)
        }

        return true // tunedProfile != nil
    }

    func roundBolus(amount: Decimal) async -> Decimal {
        let pumpSettings = await settingsManager.pumpSettings
        return deviceDataManager.roundBolus(amount: amount, maxBolus: pumpSettings.maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?
    private var bolusObserver: BolusObserver?

    func enactBolus(amount: Double, isSMB: Bool) async {
        if let error = await verifyStatus() {
            await processError(error)
            appCoordinator.sendBolusFailure()
            return
        }

//        guard let pump = pumpManager else { return }

        do {
            let roundedAmout = try deviceDataManager.roundToSupportedBolusVolume(units: amount / concentration.concentration)
            let standardInsulinAmount = try deviceDataManager.roundToSupportedBolusVolume(units: amount)

            debug(.apsManager, "Enact bolus \(roundedAmout), manual \(!isSMB)")

            try await deviceDataManager.enactBolus(units: roundedAmout, automatic: isSMB)
            debug(.apsManager, "Bolus succeeded")
            if !isSMB {
                _ = await self.determineBasal(temporaryCarbs: nil)
            }
            appCoordinator.setBolusProgress(0) // TODO: should it be nil?
//            self.bolusProgress.send(0)
            appCoordinator.setBolusAmount(Decimal(standardInsulinAmount))
//            self.bolusAmount.send(Decimal(standardInsulinAmount))
        } catch {
            warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
            await processError(APSError.pumpError(error))
            if !isSMB {
                appCoordinator.sendBolusFailure()
            }
        }
    }

    func cancelBolus() async {
        do {
            guard let pumpStatus = appCoordinator.pumpStatus.value else {
                throw APSError.invalidPumpState(message: "Pump not set")
            }
            guard pumpStatus.isBolusing else { return }
            debug(.apsManager, "Cancel bolus")
            _ = try await deviceDataManager.cancelBolus()
            debug(.apsManager, "Bolus cancelled")
        } catch {
            debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
            await processError(APSError.pumpError(error))
        }
        await clearBolusReporter()
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) async {
        if let error = await verifyStatus() {
            await processError(error)
            return
        }

//        guard let pump = pumpManager else { return }

        // unable to do temp basal during manual temp basal 😁
        if appCoordinator.manualTempBasal.value {
            await processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
            return
        }

        let pumpSettings = await settingsManager.pumpSettings

        let maxBasal = Double(pumpSettings.maxBasal)
        let rate = duration > 0 ? min(rate, maxBasal) : rate

        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        do {
            let roundedAmout = try deviceDataManager.roundToSupportedBasalRate(unitsPerHour: rate)
            let adjusted = try deviceDataManager.roundToSupportedBasalRate(unitsPerHour: rate * concentration.concentration)

            try await deviceDataManager.enactTempBasal(unitsPerHour: roundedAmout, for: duration)
            debug(.apsManager, "Temp Basal succeeded")
            let temp = TempBasal(
                duration: Int(duration / 60),
                rate: Decimal(adjusted),
                temp: .absolute,
                timestamp: Date()
            )
            await self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
            if rate == 0, duration == 0 {
                // TODO: should this be here?
                await self.pumpHistoryStorage.saveCancelTempEvents()
            }
        } catch {
            debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
            await processError(APSError.pumpError(error))
        }
    }

    func dailyAutotune() async -> Bool {
        let settings = await settingsManager.settings
        guard settings.useAutotune else {
            return false
        }

        let now = Date()

        guard lastAutotuneDate.isBeforeDate(now, granularity: .day) else {
            return false
        }
        lastAutotuneDate = now

        return await autotune() != nil
    }

    func autotune() async -> Autotune? {
        await openAPS.autotune()
    }

    func enactAnnouncement(_ announcement: Announcement) async {
        guard let action = announcement.action else {
            warning(.apsManager, "Invalid Announcement action")
            return
        }

        debug(.apsManager, "Start enact announcement: \(action)")

        let insulinConcentration = concentration
        let settings = await settingsManager.settings

        switch action {
        case let .bolus(amount):
            if let error = await verifyStatus() {
                await processError(error)
                return
            }

            guard !activeBolusView() else {
                debug(.apsManager, "Not enacting while in Bolus View")
                await processError(APSError.activeBolusViewBolus)
                return
            }

            do {
                let roundedAmount = try deviceDataManager
                    .roundToSupportedBolusVolume(units: Double(amount) / insulinConcentration.concentration)
                try await deviceDataManager.enactBolus(units: roundedAmount, automatic: false)
                debug(
                    .apsManager,
                    "Announcement Bolus succeeded."
                )
                await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                appCoordinator.setBolusProgress(0)
                appCoordinator.setBolusAmount(amount.roundBolusIncrements(increment: insulinConcentration.concentration / 0.05))
            } catch {
                // warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                switch error {
                case APSError.pumpError(PumpManagerError.uncertainDelivery):
                    // Do not generate notification on uncertain delivery error
                    // TODO: need to handle this
                    break
                default:
                    // Do not generate notifications for automatic boluses that fail.
                    warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                }
            }

        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                if let error = await verifyStatus() {
                    await processError(error)
                    return
                }
                do {
                    try await deviceDataManager.suspendDelivery()
                    debug(.apsManager, "Pump suspended by Announcement")
                    await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    // TODO: this should not be directly here
                    await self.nightscout.uploadStatus()
                } catch {
                    debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                }

            case .resume:
                do {
                    guard let pumpStatus = appCoordinator.pumpStatus.value, pumpStatus.isSuspended else {
                        return
                    }

                    try await deviceDataManager.resumeDelivery()
                    debug(.apsManager, "Pump resumed by Announcement")
                    await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    // TODO: this should not be directly here
                    await self.nightscout.uploadStatus()
                } catch {
                    warning(.apsManager, "Pump not resumed by Announcement: \(error.localizedDescription)")
                }
            }
        case let .looping(closedLoop):
            await settingsManager.updateSettings { settings in
                var updated = settings
                updated.closedLoop = closedLoop
                return updated
            }
            debug(.apsManager, "Closed loop \(closedLoop) by Announcement")
            await announcementsStorage.storeAnnouncements([announcement], enacted: true)
        case let .tempbasal(rate, duration):
            if let error = await verifyStatus() {
                await processError(error)
                return
            }

            guard !activeBolusView() || (activeBolusView() && rate == 0) else {
                debug(.apsManager, "Not enacting while in Bolus View")
                await processError(APSError.activeBolusViewBasal)
                return
            }

            // unable to do temp basal during manual temp basal 😁
            if appCoordinator.manualTempBasal.value {
                await processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                return
            }
            guard !settings.closedLoop else {
                return
            }

            do {
                let roundedRate = try deviceDataManager
                    .roundToSupportedBasalRate(unitsPerHour: Double(rate) / insulinConcentration.concentration)
                try await deviceDataManager.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration) * 60)
                debug(.apsManager, "Announcement TempBasal succeeded.")
                await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
            } catch {
                warning(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
            }

        case let .meal(carbs, fat, protein, fiber):
            let date = announcement.createdAt.date
            let fibers = fiber ?? 0

            guard carbs > 0 || fat > 0 || protein > 0 || fibers > 0 else {
                return
            }

            let item = [CarbsEntry(
                id: UUID().uuidString,
                createdAt: date,
                actualDate: date,
                carbs: carbs,
                fat: fat,
                protein: protein,
                fiber: fiber,
                note: "Remote",
                enteredBy: "Nightscout operator",
                isFPU: false
            )]

            CoreDataStorage().saveMeal(item, now: date, savedToFile: true)
            await carbsStorage.storeCarbs(item)

            await announcementsStorage.storeAnnouncements([announcement], enacted: true)
            debug(
                .apsManager,
                "Remote Meal by Announcement succeeded. Carbs: \(carbs), fat: \(fat), protein: \(protein)."
            )
        case let .override(name):
            guard !name.isEmpty else { return }
            let lastActiveOveride = overrideStorage.fetchLatestOverride().first
            let isActive = lastActiveOveride?.enabled ?? false

            // Command to Cancel Active Override
            if name.lowercased() == "cancel", isActive {
                if let activeOveride = lastActiveOveride {
                    let presetName = overrideStorage.isPresetName()
                    let nsString = presetName ?? activeOveride.percentage.formatted()

                    if let duration = overrideStorage.cancelProfile() {
                        await nightscout.editOverride(nsString, duration, activeOveride.date ?? Date.now)
                    }
                    await announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    debug(.apsManager, "Override Canceled by Announcement succeeded.")
                }
                return
            }

            // Cancel eventual current active override first
            if isActive {
                if let duration = overrideStorage.cancelProfile(), let last = lastActiveOveride {
                    let presetName = overrideStorage.isPresetName()
                    let nsString = presetName ?? last.percentage.formatted()
                    await nightscout.editOverride(nsString, duration, last.date ?? Date())
                }
            }

            // Activate the new override and uplad the new ovderride to NS. Some duplicate code now. Needs refactoring.
            let preset = overrideStorage.fetchPreset(name)
            guard let id = preset.id, let preset_ = preset.preset else { return }
            overrideStorage.overrideFromPreset(preset_, id)
            let currentActiveOveride = overrideStorage.fetchLatestOverride().first
            await nightscout.uploadOverride(
                name,
                Double(truncating: preset.preset?.duration ?? 0),
                currentActiveOveride?.date ?? Date.now
            )
            await announcementsStorage.storeAnnouncements([announcement], enacted: true)
            debug(.apsManager, "Remote Override by Announcement succeeded.")
        }
    }

    private func adjustForConcentration(_ rate: Decimal) -> Decimal {
        guard rate > 0 else { return rate }
        let setting = concentration
        guard setting.concentration != 1 else { return rate }

        return (rate * Decimal(setting.concentration)).roundBolusIncrements(increment: setting.increment)
    }

    private func currentTemp(date: Date) async -> TempBasal {
        func defaultTemp() async -> TempBasal {
            guard let temp = await storage.retrieve(OpenAPS.Monitor.tempBasal, as: TempBasal.self) else {
                return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
            }
            let delta = Int((date.timeIntervalSince1970 - temp.timestamp.timeIntervalSince1970) / 60)
            let duration = max(0, temp.duration - delta)
            return TempBasal(duration: duration, rate: temp.rate, temp: .absolute, timestamp: date)
        }

        do {
            // pumpManager?.status.basalDeliveryState
            let state = try deviceDataManager.pumpManagerStatus().basalDeliveryState
            switch state {
            case .active:
                return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
            case let .tempBasal(dose):
                let rate = adjustForConcentration(Decimal(dose.unitsPerHour))
                let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
                return TempBasal(duration: durationMin, rate: rate, temp: .absolute, timestamp: date)
            default:
                return await defaultTemp()
            }
        } catch {
            return await defaultTemp()
        }
    }

    private func enactSuggested(suggested: Suggestion) async throws {
//        guard let suggested = await storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self) else {
//            throw APSError.apsError(message: "Suggestion not found")
//        }

        guard Date().timeIntervalSince(suggested.deliverAt ?? .distantPast) < Config.eхpirationInterval else {
            throw APSError.apsError(message: "Suggestion expired")
        }

//        guard let pump = pumpManager else {
//            throw APSError.apsError(message: "Pump not set")
//        }

        // unable to do temp basal during manual temp basal 😁
        if appCoordinator.manualTempBasal.value {
            throw APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp")
        }

        let insulinSetting = concentration

        if let error = await self.verifyStatus() {
            throw error
        }

        func doBasal() async throws {
            guard let rate = suggested.rate, let duration = suggested.duration else {
                // It is OK, no temp required
                debug(.apsManager, "No temp required")
                return
            }

            guard !self.activeBolusView() || (self.activeBolusView() && rate == 0) else {
                if suggested.units != nil {
                    throw APSError.activeBolusViewBasalandBolus
                }
                throw APSError.activeBolusViewBasal
            }

            try await deviceDataManager.enactTempBasal(
                unitsPerHour: Double(rate) / insulinSetting.concentration,
                for: TimeInterval(duration * 60)
            )
            let temp = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: Date())
            await self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
        }

        func doBolus() async throws {
            guard let units = suggested.units else {
                // It is OK, no bolus required
                debug(.apsManager, "No bolus required")
                return
            }

            guard !self.activeBolusView() else {
                throw APSError.activeBolusViewBolus
            }

            try await deviceDataManager.enactBolus(units: Double(units) / insulinSetting.concentration, automatic: true)
            appCoordinator.setBolusProgress(0)
            appCoordinator.setBolusAmount(units)
        }

        try await doBasal()
        try await doBolus()
    }

    private func reportEnacted(received: Bool) async {
        if let suggestion = await storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self), suggestion.deliverAt != nil {
            var enacted = suggestion
            enacted.timestamp = Date()
            enacted.recieved = received

            await storage.save(enacted, as: OpenAPS.Enact.enacted)

            // Save to CoreData also. TO DO: Remove the JSON saving after some testing.
            let coredataContext = CoreDataStack.shared.persistentContainer.newBackgroundContext()
            let lastLoopIob = (enacted.iob ?? 0) as NSDecimalNumber
            let lastLoopCob = (enacted.cob ?? 0) as NSDecimalNumber
            let lastLoopTimestamp = received ? enacted.timestamp : coreDataStorage.fetchLastLoop()?.timestamp ?? .distantPast
            await coredataContext.perform {
                let saveLastLoop = LastLoop(context: coredataContext)
                saveLastLoop.iob = lastLoopIob
                saveLastLoop.cob = lastLoopCob
                saveLastLoop.timestamp = lastLoopTimestamp
                try? coredataContext.save()
            }

            debug(.apsManager, "Suggestion enacted. Received: \(received)")
            appCoordinator.sendEnactedSuggestion(enacted)
            // TODO: move this to nigthscout manager, listen to appCoordinator.loopCompleted
            await nightscout.uploadStatus()

            appCoordinator.sendLoopCompleted()
        }
    }

    private static func roundDouble(_ double: Double, _ digits: Double) -> Double {
        let rounded = round(Double(double) * pow(10, digits)) / pow(10, digits)
        return rounded
    }

    private func activeBolusView() -> Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: IAPSconfig.inBolusView)
    }

    private func persistLoopStats(loopStatRecord: LoopStats, error: Error?) {
        coredataContext.performAndWait {
            let nLS = LoopStatRecord(context: coredataContext)
            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0
            if let error = error {
                nLS.error = error.localizedDescription.string
            }
            try? self.coredataContext.save()
        }
    }

    private func processError(_ error: Error) async {
        warning(.apsManager, "\(error.localizedDescription)")
        appCoordinator.setLastLoopError(error)
    }

    private func removeBolusReporter() {
        if let bolusObserver, let bolusReporter {
            bolusReporter.removeObserver(bolusObserver)
        }
        bolusReporter = nil
        bolusObserver = nil
    }

    private func createBolusReporter() {
        removeBolusReporter()
        do {
            bolusReporter = try deviceDataManager.createBolusProgressReporter(reportingOn: processQueue)
            let observer = BolusObserver(manager: self)
            bolusObserver = observer
            bolusReporter?.addObserver(observer)
        } catch {
            warning(.apsManager, "failed to create bolus reporter: \(error.localizedDescription)")
        }
    }

    private func clearBolusReporter() async {
        removeBolusReporter()
        try? await Task.sleep(for: .seconds(0.5))
        self.appCoordinator.setBolusProgress(nil)
    }

    fileprivate func updateBolusProgress(percentComplete: Double, isComplete: Bool) async {
        appCoordinator.setBolusProgress(Decimal(percentComplete))
        if isComplete {
            await clearBolusReporter()
        }
    }
}

private class BolusObserver: DoseProgressObserver {
    let manager: BaseAPSManager

    init(manager: BaseAPSManager) {
        self.manager = manager
    }

    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        Task {
            await manager.updateBolusProgress(
                percentComplete: doseProgressReporter.progress.percentComplete,
                isComplete: doseProgressReporter.progress.isComplete
            )
        }
    }
}
