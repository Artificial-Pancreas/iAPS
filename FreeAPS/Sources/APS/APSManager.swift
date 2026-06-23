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
    ) async throws -> Suggestion
//    func determineBasalSync()
//    func iobSync() async -> Decimal?
    func roundBolus(amount: Decimal) async -> Decimal
//    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus() async
    func enactAnnouncement(_ announcement: Announcement) async
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case pumpNotConfigured
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
        case .pumpNotConfigured:
            return "Pump not configured"
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

    private let coreDataStorage = CoreDataStorage()

    let lifetime = Lifetime()

    private var wasManualTempBasal = false

    private var concentration: (concentration: Double, increment: Double) {
        get async {
            await coreDataStorage.insulinConcentration()
        }
    }

    private var override: OverrideSnapshot? {
        guard let last = overrideStorage.fetchLatestOverrideSnapshot(), last.enabled else { return nil }
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
        let lastSuggested = await storage.retrieve(OpenAPS.Enact.suggested, as: Suggestion.self)

        appCoordinator.setLatestSuggestion(lastSuggested)

        if let lastOutcome = await storage.retrieve(OpenAPS.Enact.outcome, as: LoopOutcome.self) {
            appCoordinator.restorePersistedLoopOutcome(lastOutcome)
        }

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
        await updateIOB()

        observe(appCoordinator.pumpHistory.dropFirst()) { me, _ in
            guard !me.appCoordinator.isLooping.value else {
                // loop will update IOB at the end
                return
            }
            await me.updateIOB()
        }
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
        let settings = appCoordinator.settings.value

        guard !appCoordinator.isLooping.value else {
            warning(.apsManager, "Loop already in progress. Skip recommendation.")
            return
        }

        // check the last start of looping is more the loopInterval but the previous loop was completed
        if lastLoopDate > lastStartLoopDate {
            let loopInterval = settings.allowOneMinuteLoop ? Config.loopIntervalOneMinute : Config.loopIntervalFiveMinutes
            guard Date().timeIntervalSince(lastStartLoopDate) >= loopInterval else {
                debug(.apsManager, "too close to do a loop : \(lastStartLoopDate)")
                return
            }
        }

        appCoordinator.setIsLooping(true)

        // start background time extension
        let backgroundTaskIdBox = TaskIDBox()
        let backgroundTimeRemaining = await MainActor.run { () -> TimeInterval in
            backgroundTaskIdBox.id = UIApplication.shared.beginBackgroundTask(withName: "Loop starting") {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdBox.id)
            }
            return UIApplication.shared.backgroundTimeRemaining
        }

        debug(.apsManager, "Starting loop, background time remaining: \(backgroundTimeRemaining.rounded())")

        let lastStartLoopDate = Date()
        self.lastStartLoopDate = lastStartLoopDate

        let interval = await fetchIntervalSinceLastLoop(thisLoopDate: lastStartLoopDate)

        var loopStatRecord = LoopStats(
            start: lastStartLoopDate,
            loopStatus: "Starting",
            interval: interval
        )

        let loopOutcome: LoopOutcome
        do {
            let suggestion = try await determineBasal(temporaryCarbs: nil)
            loopOutcome = await enactSuggestion(suggestion, closedLoop: settings.closedLoop)
        } catch {
            loopOutcome = .failed(error: error.localizedDescription, timestamp: Date.now)
        }

        loopStatRecord.end = Date()
        loopStatRecord.duration = Self.roundDouble(
            (loopStatRecord.end! - loopStatRecord.start).timeInterval / 60, 2
        )

        await storage.save(loopOutcome, as: OpenAPS.Enact.outcome)

        switch loopOutcome {
        case let .enacted(_, timestamp):
            lastLoopDate = timestamp
            appCoordinator.setLastLoopDate(timestamp)
            appCoordinator.setLastLoopError(nil)

            loopStatRecord.loopStatus = "Success"

        case let .enactFailed(_, error, timestamp):
            appCoordinator.setLastLoopError((error, date: timestamp))

            loopStatRecord.loopStatus = error

        case let .suggested(_, timestamp):
            lastLoopDate = timestamp
            appCoordinator.setLastLoopDate(timestamp)
            appCoordinator.setLastLoopError(nil)

            loopStatRecord.loopStatus = "Success"

        case let .failed(error, timestamp):
            appCoordinator.setLastLoopError((error, date: timestamp))

            loopStatRecord.loopStatus = error
        }

        await self.persistLoopStats(loopStatRecord: loopStatRecord, error: loopOutcome.error)

        await self.updateIOB()

        appCoordinator.setIsLooping(false)

        appCoordinator.sendLoopCompleted(loopOutcome)

        // TODO: is this a good idea?
        // give background tasks a chance to finish?
        try? await Task.sleep(for: .seconds(1))

        // end of the background tasks
        await MainActor.run {
            if backgroundTaskIdBox.id != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskIdBox.id)
            }
        }
    }

    private func fetchIntervalSinceLastLoop(thisLoopDate: Date) async -> Double? {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { coredataContext in
            let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sortStats = NSSortDescriptor(key: "end", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            let previousLoop = (try? coredataContext.fetch(requestStats)) ?? []

            if (previousLoop.first?.end ?? .distantFuture) < thisLoopDate {
                return Self.roundDouble((thisLoopDate - (previousLoop.first?.end ?? Date())).timeInterval / 60, 1)
            }
            return nil
        }
    }

    private func enactSuggestion(_ suggestion: Suggestion, closedLoop: Bool) async -> LoopOutcome {
        var suggestion = suggestion
        guard closedLoop else {
            let now = Date.now
            suggestion.timestamp = now
            return .suggested(suggestion, timestamp: now)
        }
        do {
            try await self.enactSuggested(suggested: suggestion)

            let now = Date.now
            suggestion.timestamp = now
            suggestion.recieved = true

            return .enacted(suggestion, timestamp: now)
        } catch {
            let now = Date.now
            suggestion.timestamp = now
            suggestion.recieved = false
            return .enactFailed(suggestion, error: error.localizedDescription, timestamp: now)
        }
    }

    private func verifyStatus() async -> Error? {
        guard let status = deviceDataManager.currentPumpStatus() else {
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
    ) async throws -> Suggestion {
        debug(.apsManager, "Start determine basal")
        do {
            guard let glucose = await storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self),
                  glucose.isNotEmpty
            else {
                debug(.apsManager, "Not enough glucose data")
                throw APSError.glucoseError(message: "Not enough glucose data")
            }

            let lastGlucoseDate = await glucoseStorage.latestDate() ?? .distantPast
            guard lastGlucoseDate > Date().addingTimeInterval(-12.minutes.timeInterval) else {
                debug(.apsManager, "Glucose data is stale")
                throw APSError.glucoseError(message: "Glucose data is stale")
            }

            guard let pumpStatus = deviceDataManager.currentPumpStatus() else {
                throw APSError.invalidPumpState(message: "Pump not set")
            }

            let settings = appCoordinator.settings.value
            let preferences = appCoordinator.preferences.value

            let now = Date()
            let temp = try await currentTemp()

            if temp.duration == 0,
               settings.closedLoop,
               preferences.unsuspendIfNoTemp,
               pumpStatus.isSuspended
            {
                do {
                    try await deviceDataManager.resumeDelivery()
                } catch {
                    debug(.apsManager, "failed to resume delivery: \(error.localizedDescription)")
                    throw APSError.apsError(message: "failed to resume delivery: \(error.localizedDescription)")
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
            guard let suggestion else {
                throw APSError.apsError(message: "Determine basal failed")
            }
            await storage.save(suggestion, as: OpenAPS.Enact.suggested)
            appCoordinator.setLatestSuggestion(suggestion)
            return suggestion
        } catch {
            processError(error)
            throw error
        }
    }

    private func updateIOB() async {
        let sync = await openAPS.iobSync()
        guard let iobEntries = IOBEntry.parseArrayFromJSON(from: sync) else { return }

        _ = await coreDataStorage.saveInsulinData(iobEntries: iobEntries)

        appCoordinator.setIobTicks(iobEntries)
    }

    func makeProfiles() async -> Bool {
        let settings = await settingsManager.settings
        let tunedProfile = await openAPS.makeProfiles(useAutotune: settings.useAutotune, settings: settings)

        if let basalProfile = tunedProfile?.basalProfile {
            appCoordinator.sendBasalProfile(basalProfile)
        }

        return true // tunedProfile != nil
    }

    func roundBolus(amount: Decimal) async -> Decimal {
        let pumpSettings = appCoordinator.pumpSettings.value
        return deviceDataManager.roundBolus(amount: amount, maxBolus: pumpSettings.maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?
    private var bolusObserver: BolusObserver?

    func enactBolus(amount: Double, isSMB: Bool) async {
        if let error = await verifyStatus() {
            processError(error)
            appCoordinator.sendBolusFailure()
            return
        }

        let concentration = await self.concentration
        do {
            debug(.apsManager, "Enact bolus \(amount), manual \(!isSMB)")

            let enactedAmount = try await deviceDataManager.enactBolus(
                units: Decimal(amount),
                automatic: isSMB,
                concentration: concentration.concentration
            )
            debug(.apsManager, "Bolus succeeded")
            if !isSMB {
                _ = try? await self.determineBasal(temporaryCarbs: nil)
            }
            appCoordinator.setBolusProgress(0)
            appCoordinator.setBolusAmount(enactedAmount)
        } catch {
            warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
            if !isSMB {
                appCoordinator.sendBolusFailure()
            }
        }
    }

    func cancelBolus() async {
        do {
            guard let pumpStatus = deviceDataManager.currentPumpStatus() else {
                throw APSError.invalidPumpState(message: "Pump not set")
            }
            guard pumpStatus.isBolusing else { return }
            debug(.apsManager, "Cancel bolus")
            try await deviceDataManager.cancelBolus()
            debug(.apsManager, "Bolus cancelled")
        } catch {
            debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
        }
        await clearBolusReporter()
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) async {
        if let error = await verifyStatus() {
            processError(error)
            return
        }

        // unable to do temp basal during manual temp basal 😁
        if appCoordinator.manualTempBasal.value {
            processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
            return
        }

        let pumpSettings = await settingsManager.pumpSettings

        let maxBasal = Double(pumpSettings.maxBasal)
        let rate = duration > 0 ? min(rate, maxBasal) : rate

        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        let concentration = await self.concentration

        do {
            try await deviceDataManager.enactTempBasal(
                unitsPerHour: Decimal(rate),
                for: duration,
                concentration: concentration.concentration
            )
        } catch {
            debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
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

        let insulinConcentration = await concentration
        let settings = await settingsManager.settings

        switch action {
        case let .bolus(amount):
            if let error = await verifyStatus() {
                processError(error)
                return
            }

            guard !activeBolusView() else {
                debug(.apsManager, "Not enacting while in Bolus View")
                processError(APSError.activeBolusViewBolus)
                return
            }

            do {
                let enactedAmount = try await deviceDataManager.enactBolus(
                    units: amount,
                    automatic: false,
                    concentration: insulinConcentration.concentration
                )
                debug(
                    .apsManager,
                    "Announcement Bolus succeeded."
                )
                await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                appCoordinator.setBolusProgress(0)
                appCoordinator.setBolusAmount(enactedAmount)
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
                    processError(error)
                    return
                }
                do {
                    try await deviceDataManager.suspendDelivery()
                    debug(.apsManager, "Pump suspended by Announcement")
                    await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    // TODO: this should not be directly here
                } catch {
                    debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                }

            case .resume:
                do {
                    guard let pumpStatus = deviceDataManager.currentPumpStatus(), pumpStatus.isSuspended else {
                        return
                    }

                    try await deviceDataManager.resumeDelivery()
                    debug(.apsManager, "Pump resumed by Announcement")
                    await self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    // TODO: this should not be directly here
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
                processError(error)
                return
            }

            guard !activeBolusView() || (activeBolusView() && rate == 0) else {
                debug(.apsManager, "Not enacting while in Bolus View")
                processError(APSError.activeBolusViewBasal)
                return
            }

            // unable to do temp basal during manual temp basal 😁
            if appCoordinator.manualTempBasal.value {
                processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                return
            }
            guard !settings.closedLoop else {
                return
            }

            do {
                try await deviceDataManager.enactTempBasal(
                    unitsPerHour: rate,
                    for: TimeInterval(duration) * 60,
                    concentration: insulinConcentration.concentration
                )
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

            await coreDataStorage.saveMeal(item, now: date, savedToFile: true)
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
                        await nightscout.uploadOverride(nsString, duration, activeOveride.date ?? Date.now)
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
                    await nightscout.uploadOverride(nsString, duration, last.date ?? Date())
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

    private func currentTemp() async throws -> TempBasal {
        let concentration = await self.concentration
        return try deviceDataManager.currentTempBasal(concentration: concentration.concentration)
    }

    private func enactSuggested(suggested: Suggestion) async throws {
        do {
            guard Date().timeIntervalSince(suggested.deliverAt ?? .distantPast) < Config.eхpirationInterval else {
                throw APSError.apsError(message: "Suggestion expired")
            }

            // unable to do temp basal during manual temp basal 😁
            if appCoordinator.manualTempBasal.value {
                throw APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp")
            }

            let insulinSetting = await concentration

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

                if let error = await self.verifyStatus() {
                    throw error
                }

                try await deviceDataManager.enactTempBasal(
                    unitsPerHour: rate,
                    for: TimeInterval(duration * 60),
                    concentration: insulinSetting.concentration
                )
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

                if let error = await self.verifyStatus() {
                    throw error
                }

                let enactedAmount = try await deviceDataManager.enactBolus(
                    units: units,
                    automatic: true,
                    concentration: insulinSetting.concentration
                )
                appCoordinator.setBolusProgress(0)
                appCoordinator.setBolusAmount(enactedAmount)
            }

            try await doBasal()
            try await doBolus()
        } catch {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
            throw error
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

    private func persistLoopStats(loopStatRecord: LoopStats, error: String?) async {
        await CoreDataStack.shared.persistentContainer.performBackgroundTask { coredataContext in
            let nLS = LoopStatRecord(context: coredataContext)
            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0
            if let error = error {
                nLS.error = error
            }
            try? coredataContext.save()
        }
    }

    private func processError(_ error: Error) {
        warning(.apsManager, "\(error.localizedDescription)")
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
        let percentComplete = doseProgressReporter.progress.percentComplete
        let isComplete = doseProgressReporter.progress.isComplete
        Task { [manager] in
            await manager.updateBolusProgress(
                percentComplete: percentComplete,
                isComplete: isComplete
            )
        }
    }
}
