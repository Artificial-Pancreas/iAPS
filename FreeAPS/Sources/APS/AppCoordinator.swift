import Combine
import Foundation
import LoopKit
import UIKit

// @unchecked Sendable - this class only contains immutable `let`s holding Combine subjects,
// which are internally thread-safe for concurrent send/value/subscribe.
// (and one lock-guarded counter, `mealsChangeCount`)
// TODO: values flow across isolation domains via these subjects, so Output types should be Sendable (Combine won't enforce this).
// * `Error` is not Sendable; we need to either replace it with something that is Sendable, or accepted as is - since those values are effectively immutable.

// WARN: Sometimes, when a field is added/removed in this class, and after an INCREMENTAL build - the app crashes at runtime.
// A full rebuild completely fixes the issue in such cases (Product / Clean Build Folder).
// TODO: investigate this
final class AppCoordinator: @unchecked Sendable {
    // initial values will not be observed by tha app, SettingsManager sets the real values in its start(), and the app won't render before it's finished
    let settings = CurrentValueSubject<FreeAPSSettings, Never>(FreeAPSSettings())
    let pumpSettings = CurrentValueSubject<PumpSettings, Never>(PumpSettings.defaultValue)
    let preferences = CurrentValueSubject<Preferences, Never>(Preferences())

    // -----

    let pumpInfo = CurrentValueSubject<PumpDisplayInfo?, Never>(nil)

    let pumpStatus = CurrentValueSubject<PumpDisplayStatus?, Never>(nil)

    let cgmInfo = CurrentValueSubject<CgmDisplayInfo?, Never>(nil)

    let cgmStatus = CurrentValueSubject<CgmDisplayStatus?, Never>(nil)

    // -----

    let heartbeat = PassthroughSubject<Void, Never>()

    let recommendsLoop = PassthroughSubject<Void, Never>()

    let isLooping = CurrentValueSubject<Bool, Never>(false)

    let manualTempBasal = CurrentValueSubject<Bool, Never>(false)

    let deliveryUncertain = PassthroughSubject<Void, Never>()

    let deviceErrors = PassthroughSubject<Error, Never>()

    let alertNotAckUpdates = CurrentValueSubject<Bool, Never>(false)

    // loop failures and device problems, newest -> oldest
    let loopEvents = CurrentValueSubject<[LoopEvent], Never>([])

    let latestLoopOutcome = CurrentValueSubject<LoopOutcome?, Never>(nil)

    let loopCompleted = PassthroughSubject<LoopOutcome, Never>()

    // periods without loop cycles, derived from the recorded loop cycles, newest -> oldest
    let loopGaps = CurrentValueSubject<[LoopGap], Never>([])

    // current pump history, newest -> oldest
    let pumpHistory = CurrentValueSubject<[PumpHistoryEvent], Never>([])

    let pumpHistoryDeletions = PassthroughSubject<[PumpHistoryEvent], Never>()

    // the pump driver's change events (a pod or patch, an infusion set, a reservoir) of one hasNewPumpEvents call, as
    // they came; sent from DeviceDataManager only, before it stores the events. Statistics only (PumpEventStore)
    let pumpLifecycleEvents = PassthroughSubject<[PumpLifecycleEvent], Never>()

    // the stored insulin data (PumpEvent / BasalScheduleRecord rows, the Reasons IOB) changed; sent after the save,
    // by the writers only (PumpEventStore, CoreDataManager's Reasons save, the Settings wipe of Reasons)
    let insulinDataChanged = PassthroughSubject<InsulinDataChange, Never>()

    // InsulinStatsService dropped what an insulin data change (or a time zone change) touched: recompute the Insulin tab.
    // Sent from the InsulinStatsService actor only (one sender, so seq grows by one per change); the glucoseStatsChanged
    // contract: subscribe with observe / observeUI (they hop), cancel the refresh in flight and drop a cancelled result.
    let insulinStatsChanged = CurrentValueSubject<StatsChange, Never>(StatsChange(seq: 0, interval: nil))

    // newest -> oldest
    let glucoseRaw = CurrentValueSubject<[BloodGlucose], Never>([])

    // newest -> oldest
    // when smoothing is disabled, this is equal to glucoseRaw
    let glucoseSmoothed = CurrentValueSubject<[BloodGlucose], Never>([])

    // newest -> oldest
    // this contains the glucose from glucoseSmoothed filtered by 5min frequency
    // this is consumed by OpenAPS, passed to oref0
    let glucoseFrequencyFiltered = CurrentValueSubject<[BloodGlucose], Never>([])

    let glucoseDeletions = PassthroughSubject<[BloodGlucose], Never>()

    // the stored Readings (Core Data) were inserted, deleted or changed; sent after the save
    let readingsChanged = PassthroughSubject<ReadingsChange, Never>()

    // GlucoseStatistics dropped what a readings change (or a time zone change) touched: recompute the statistics.
    // The only refresh trigger for them (not glucoseSmoothed, which comes before the Core Data save). Sent from the
    // GlucoseStatistics actor, so Combine runs a subscriber inline on it: subscribe with observe / observeUI (they hop),
    // never do synchronous work in a sink. On every change cancel the refresh in flight and drop a cancelled result.
    let glucoseStatsChanged = CurrentValueSubject<StatsChange, Never>(StatsChange(seq: 0, interval: nil))

    // periods without readings, derived from the glucose history, newest -> oldest
    let glucoseGaps = CurrentValueSubject<[GlucoseGap], Never>([])

    let glucoseAlarm = CurrentValueSubject<GlucoseAlarm?, Never>(nil)

    let iobTicks = CurrentValueSubject<[IOBEntry]?, Never>(nil)

    /// Rolling ~24h of stored IOB/activity samples (from `InsulinActivity` store
    let insulinActivity = CurrentValueSubject<[IOBEntryShort], Never>([])

    let suggested = CurrentValueSubject<Suggestion?, Never>(nil)

    let newGlucoseRecords = PassthroughSubject<[BloodGlucose], Never>()

    // current carb history, newest -> oldest
    let carbHistory = CurrentValueSubject<[CarbsEntry], Never>([])

    let carbDeletions = PassthroughSubject<[CarbsEntry], Never>()

    // the Meals rows or the carbs file changed (CarbsStorage, only when something did; the Settings wipe of Meals): the
    // Meals tab refreshes on it. A counter, bumped and sent under one lock (`sendMealsChanged`), so every subscriber gets
    // the values in order, one more per change, across senders. Subscribe with observe / observeUI (they hop): a plain
    // sink runs inside the lock, so it must not wait on another sender, and must not call sendMealsChanged itself (the
    // lock is recursive, so that doesn't deadlock, but its nested value then reaches the later subscribers first).
    let mealsChanged = CurrentValueSubject<Int, Never>(0)

    // current temp targets, newest -> oldest
    let tempTargets = CurrentValueSubject<[TempTarget], Never>([])

    /// Latches once the UI is subscribed to `alertMessages`. `DeviceAlertManager` waits for it before
    /// replaying alerts left outstanding by the previous run - a `CurrentValueSubject` rather than an
    /// event because the two sides start in no fixed order, and a replay sent into a bus nobody is
    /// listening to yet is simply lost.
    let alertPresentationReady = CurrentValueSubject<Bool, Never>(false)
    let basalProfile = CurrentValueSubject<[BasalProfileEntry], Never>([])

    let isfSchedule = CurrentValueSubject<InsulinSensitivities, Never>(.initial)

    let crSchedule = CurrentValueSubject<CarbRatios, Never>(.initial)

    let bgTargetsSchedule = CurrentValueSubject<BGTargets, Never>(.initial)

    let autotune = CurrentValueSubject<Profile?, Never>(nil)

    let profile = CurrentValueSubject<Profile?, Never>(nil)

    let pumpProfile = CurrentValueSubject<Profile?, Never>(nil)

    let autosens = CurrentValueSubject<Autosens?, Never>(nil)

    let lastLoopDate = CurrentValueSubject<Date?, Never>(nil)

    let lastLoopError = CurrentValueSubject<(error: String, date: Date)?, Never>(nil)

    let bolusFailures = PassthroughSubject<Void, Never>()

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    let bolusAmount = CurrentValueSubject<Decimal?, Never>(nil)

    // the pump reports .canceling for the bolus the progress bar shows (kept through the bar's linger)
    let bolusCanceling = CurrentValueSubject<Bool, Never>(false)

    // a cancel requested from iAPS is running (APSManager.cancelBolus)
    let bolusCancelInFlight = CurrentValueSubject<Bool, Never>(false)

    // the pump reports .initiating for a bolus iAPS enacted: the requested amount (standard units)
    let bolusStarting = CurrentValueSubject<Decimal?, Never>(nil)

    // how the last cancel of the bolus the bar shows went wrong (nil: nothing to tell)
    let bolusCancelOutcome = CurrentValueSubject<BolusCancelOutcome?, Never>(nil)

    let newSensorDetectedEvents = PassthroughSubject<Void, Never>()

    let liveActivitiesSystemEnabled = CurrentValueSubject<Bool, Never>(false)

    let alertMessages = PassthroughSubject<AlertMessage, Never>()

    let appBecomeActiveEvents = PassthroughSubject<Void, Never>()

    let nightscoutConfigChanged = PassthroughSubject<Void, Never>()

    // bumped whenever override-related CoreData entities change
    let overridesChanged = CurrentValueSubject<Date, Never>(.distantPast)

    // bumped whenever the temp target presets change (they are not published as temp targets)
    let tempTargetPresetsChanged = CurrentValueSubject<Date, Never>(.distantPast)

    /// Fires when DatabaseManager stores a published-versions check (the VNr table); Home
    /// recomputes its newer-release notice from it instead of polling on the loop path.
    let versionCheckStored = CurrentValueSubject<Date, Never>(.distantPast)

    // --------------

    private let loopPendingBackgroundTask = TaskIDBox()

    /// `mealsChanged`'s lock: the increment and the send happen together. Recursive: a send from a subscriber (a misuse)
    /// nests instead of deadlocking
    private let mealsChangeLock = NSRecursiveLock()
    /// guarded by `mealsChangeLock` (the class's one var: @unchecked Sendable through the lock)
    private var mealsChangeCount = 0

    // --------------

    func setSettings(_ value: FreeAPSSettings) {
        settings.send(value)
    }

    func setPreferences(_ value: Preferences) {
        preferences.send(value)
    }

    func setPumpSettings(_ value: PumpSettings) {
        pumpSettings.send(value)
    }

    func setIsLooping(_ value: Bool) {
        isLooping.send(value)
    }

    func setPumpInfo(_ value: PumpDisplayInfo?) {
        pumpInfo.send(value)
    }

    func setPumpStatus(_ value: PumpDisplayStatus?) {
        pumpStatus.send(value)
    }

    func setCgmInfo(_ value: CgmDisplayInfo?) {
        cgmInfo.send(value)
    }

    func setCgmStatus(_ value: CgmDisplayStatus?) {
        cgmStatus.send(value)
    }

    func sendHeartbeat() {
        heartbeat.send(())
    }

    func setAlertNotAck(_ value: Bool) {
        alertNotAckUpdates.send(value)
    }

    func setLastLoopDate(_ value: Date?) {
        lastLoopDate.send(value)
    }

    func overridesDidChange() {
        overridesChanged.send(Date())
    }

    func tempTargetPresetsDidChange() {
        tempTargetPresetsChanged.send(Date())
    }

    func versionCheckDidStore() {
        versionCheckStored.send(Date())
    }

    func setLastLoopError(_ value: (String, date: Date)?) {
        if let value {
            lastLoopError.send((error: value.0, date: value.date))
        } else {
            lastLoopError.send(nil)
        }
    }

    func sendDeviceError(_ value: Error) {
        deviceErrors.send(value)
    }

    /// MUST BE newest -> oldest
    func setLoopEvents(_ value: [LoopEvent]) {
        loopEvents.send(value)
    }

    // make sure we have a running background task after the device data manager recommends the loop and before the actual loop starts
    func startLoopPendingBackgroundTask() async {
        let box = loopPendingBackgroundTask
        await MainActor.run {
            // multiple backfill readings can trigger this more than once before the loop is started (as intended)
            // we don't start another background tasks if one is already running
            guard box.id == .invalid else { return }
            box.id = UIApplication.shared.beginBackgroundTask(withName: "loop pending") {
                if box.id != .invalid {
                    warning(
                        .deviceManager,
                        "loop has not started in time after loop was recommended, the 'pending' background task timed out"
                    )
                    UIApplication.shared.endBackgroundTask(box.id)
                    box.id = .invalid
                }
            }
        }
    }

    // this is called right after a loop background task starts
    func endLoopPendingBackgroundTask() async {
        let box = loopPendingBackgroundTask
        await MainActor.run {
            if box.id != .invalid {
                UIApplication.shared.endBackgroundTask(box.id)
                box.id = .invalid
            }
        }
    }

    func sendRecommendsLoop() {
        recommendsLoop.send(())
    }

    func setManualTempBasal(_ value: Bool) {
        manualTempBasal.send(value)
    }

    func setIobTicks(_ value: [IOBEntry]?) {
        iobTicks.send(value)
    }

    func setInsulinActivity(_ value: [IOBEntryShort]) {
        insulinActivity.send(value)
    }

    func setLatestSuggestion(_ value: Suggestion?) {
        suggested.send(value)
    }

    /// MUST BE newest -> oldest
    func setPumpHistory(_ value: [PumpHistoryEvent]) {
        pumpHistory.send(value)
    }

    func sendPumpHistoryDeleted(_ value: [PumpHistoryEvent]) {
        pumpHistoryDeletions.send(value)
    }

    func sendPumpLifecycleEvents(_ value: [PumpLifecycleEvent]) {
        pumpLifecycleEvents.send(value)
    }

    func sendInsulinDataChanged(_ value: InsulinDataChange) {
        insulinDataChanged.send(value)
    }

    func setInsulinStatsChanged(_ value: StatsChange) {
        insulinStatsChanged.send(value)
    }

    /// One more change of the meals: the counter goes up by one and is sent, both under the lock, so two senders never
    /// send the same value or send out of order.
    func sendMealsChanged() {
        mealsChangeLock.withLock {
            mealsChangeCount += 1
            mealsChanged.send(mealsChangeCount)
        }
    }

    /// MUST BE newest -> oldest
    func setCarbHistory(_ value: [CarbsEntry]) {
        carbHistory.send(value)
    }

    func sendCarbDeleted(_ value: [CarbsEntry]) {
        carbDeletions.send(value)
    }

    /// MUST BE newest -> oldest
    func setTempTargets(_ value: [TempTarget]) {
        tempTargets.send(value)
    }

    /// MUST BE newest -> oldest
    func setGlucoseHistory(raw: [BloodGlucose], smoothed: [BloodGlucose], frequencyFiltered: [BloodGlucose]) {
        glucoseRaw.send(raw)
        glucoseSmoothed.send(smoothed)
        glucoseFrequencyFiltered.send(frequencyFiltered)
    }

    /// MUST BE newest -> oldest
    func setGlucoseGaps(_ value: [GlucoseGap]) {
        glucoseGaps.send(value)
    }

    /// MUST BE newest -> oldest
    func setLoopGaps(_ value: [LoopGap]) {
        loopGaps.send(value)
    }

    func sendNewGlucoseRecords(_ value: [BloodGlucose]) {
        newGlucoseRecords.send(value)
    }

    func sendGlucoseDeleted(_ value: [BloodGlucose]) {
        glucoseDeletions.send(value)
    }

    func sendReadingsChanged(_ value: ReadingsChange) {
        readingsChanged.send(value)
    }

    func setGlucoseStatsChanged(_ value: StatsChange) {
        glucoseStatsChanged.send(value)
    }

    func setGlucoseAlarm(_ value: GlucoseAlarm?) {
        glucoseAlarm.send(value)
    }

    func setBasalProfile(_ value: [BasalProfileEntry]) {
        basalProfile.send(value)
    }

    func setIsfSchedule(_ value: InsulinSensitivities) {
        isfSchedule.send(value)
    }

    func setCrSchedule(_ value: CarbRatios) {
        crSchedule.send(value)
    }

    func setBgTargetsSchedule(_ value: BGTargets) {
        bgTargetsSchedule.send(value)
    }

    func setAutotune(_ value: Profile?) {
        autotune.send(value)
    }

    func setProfile(_ value: Profile?) {
        profile.send(value)
    }

    func setPumpProfile(_ value: Profile?) {
        pumpProfile.send(value)
    }

    func setAutosens(_ value: Autosens?) {
        autosens.send(value)
    }

    func sendBolusFailure() {
        bolusFailures.send(())
    }

    func setBolusProgress(_ value: Decimal?) {
        bolusProgress.send(value)
    }

    func setBolusAmount(_ value: Decimal?) {
        bolusAmount.send(value)
    }

    func setBolusCanceling(_ value: Bool) {
        bolusCanceling.send(value)
    }

    func setBolusCancelInFlight(_ value: Bool) {
        bolusCancelInFlight.send(value)
    }

    func setBolusStarting(_ value: Decimal?) {
        bolusStarting.send(value)
    }

    func setBolusCancelOutcome(_ value: BolusCancelOutcome?) {
        bolusCancelOutcome.send(value)
    }

    func restorePersistedLoopOutcome(_ value: LoopOutcome) {
        // set the current value subject, but don't publish the event
        latestLoopOutcome.send(value)
    }

    func sendLoopCompleted(_ value: LoopOutcome) {
        latestLoopOutcome.send(value)
        loopCompleted.send(value)
    }

    func sendDeliveryUncertain() {
        deliveryUncertain.send(())
    }

    func sendNewSensorDetected() {
        newSensorDetectedEvents.send(())
    }

    func setLiveActivitiesSystemEnabled(_ value: Bool) {
        liveActivitiesSystemEnabled.send(value)
    }

    func sendAlertMessage(_ value: MessageContent) {
        alertMessages.send(.show(value))
    }

    func sendAlertDismissalMessage(_ value: AlertIdentity) {
        alertMessages.send(.dismiss(value))
    }

    func sendAppBecomeActiveEvent() {
        appBecomeActiveEvents.send(())
    }

    func setAlertPresentationReady() {
        alertPresentationReady.send(true)
    }

    func sendNightscoutConfigChanged() {
        nightscoutConfigChanged.send()
    }
}

/// What changed in the stored Readings, for the statistics cache.
enum ReadingsChange: Sendable, Equatable {
    /// readings dated within the interval were inserted, deleted or changed. `newest`: all of them are inserted
    /// readings newer than every reading stored before (a CGM reading coming in), so only the readings just before
    /// them can be affected
    case interval(DateInterval, newest: Bool)
    /// any reading may have changed (the Settings wipe)
    case all

    /// The change of readings at these dates; nil for none.
    static func readings(at dates: [Date], newest: Bool) -> ReadingsChange? {
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return .interval(DateInterval(start: first, end: last), newest: newest)
    }
}

/// What changed in the stored insulin data, for the insulin statistics.
enum InsulinDataChange: Sendable, Equatable {
    /// rows touching the interval were inserted, deleted or changed
    case interval(DateInterval)
    /// any of them may have changed (a wipe)
    case all
}

/// The statistics changed: `seq` grows with every change.
struct StatsChange: Equatable, Sendable {
    let seq: Int
    /// the time whose statistics changed; nil for all of it
    let interval: DateInterval?
}

/// a bolus cancel that didn't go through, shown on the bolus bar until a new cancel, another bolus or the bar's clear
struct BolusCancelOutcome: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case failed // the pump refused it or the command failed
        case notConfirmed // no answer within the timeout (the call may still complete)
    }

    let kind: Kind
    // the bolus has ended and the bar only lingers: nothing to retry
    let bolusEnded: Bool
}
