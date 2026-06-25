import Combine
import Foundation
import LoopKit
import UIKit

// @unchecked Sendable - this class only contains immutable `let`s holding Combine subjects,
// which are internally thread-safe for concurrent send/value/subscribe.
// TODO: values flow across isolation domains via these subjects, so Output types should be Sendable (Combine won't enforce this).
// * `Error` is not Sendable; we need to either replace it with something that is Sendable, or accepted as is - since those values are effectively immutable.

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

    let pumpNotifications = PassthroughSubject<AlertEntry, Never>()

    // TODO: this is never triggered?
    let pumpNotificationsRemove = PassthroughSubject<Void, Never>()

    let deliveryUncertain = PassthroughSubject<Void, Never>()

    let deviceErrors = PassthroughSubject<Error, Never>()

    let alertNotAckUpdates = CurrentValueSubject<Bool, Never>(false)

    let latestLoopOutcome = CurrentValueSubject<LoopOutcome?, Never>(nil)

    let loopCompleted = PassthroughSubject<LoopOutcome, Never>()

    // current pump history, oldest -> newest
    let pumpHistory = CurrentValueSubject<[PumpHistoryEvent], Never>([])

    let pumpHistoryDeletions = PassthroughSubject<[PumpHistoryEvent], Never>()

    // newest -> oldest
    let glucoseHistory = CurrentValueSubject<[BloodGlucose], Never>([])

    let glucoseDeletions = PassthroughSubject<[BloodGlucose], Never>()

    let glucoseAlarm = CurrentValueSubject<GlucoseAlarm?, Never>(nil)

    let iobTicks = CurrentValueSubject<[IOBEntry]?, Never>(nil)

    let suggested = CurrentValueSubject<Suggestion?, Never>(nil)

    let newGlucoseRecords = PassthroughSubject<[BloodGlucose], Never>()

    // current carb history, newest -> oldest
    let carbHistory = CurrentValueSubject<[CarbsEntry], Never>([])

    let carbDeletions = PassthroughSubject<[CarbsEntry], Never>()

    // current temp targets, oldest -> newest
    let tempTargets = CurrentValueSubject<[TempTarget], Never>([])

    let alertsUpdates = PassthroughSubject<[AlertEntry], Never>()

    let basalProfileUpdates = PassthroughSubject<[BasalProfileEntry], Never>()

    let lastLoopDate = CurrentValueSubject<Date?, Never>(nil)

    let lastLoopError = CurrentValueSubject<(error: String, date: Date)?, Never>(nil)

    let bolusFailures = PassthroughSubject<Void, Never>()

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    let bolusAmount = CurrentValueSubject<Decimal?, Never>(nil)

    let newSensorDetectedEvents = PassthroughSubject<Void, Never>()

    let liveActivitiesSystemEnabled = CurrentValueSubject<Bool, Never>(false)

    let alertMessages = PassthroughSubject<MessageContent, Never>()

    let appBecomeActiveEvents = PassthroughSubject<Void, Never>()

    // --------------

    private let loopPendingBackgroundTask = TaskIDBox()

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

    func sendPumpNotification(_ value: AlertEntry) {
        pumpNotifications.send(value)
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

    func setLatestSuggestion(_ value: Suggestion?) {
        suggested.send(value)
    }

    /// MUST BE oldest -> newest
    func setPumpHistory(_ value: [PumpHistoryEvent]) {
        pumpHistory.send(value)
    }

    func sendPumpHistoryDeleted(_ value: [PumpHistoryEvent]) {
        pumpHistoryDeletions.send(value)
    }

    /// MUST BE newest -> oldest
    func setCarbHistory(_ value: [CarbsEntry]) {
        carbHistory.send(value)
    }

    func sendCarbDeleted(_ value: [CarbsEntry]) {
        carbDeletions.send(value)
    }

    /// MUST BE oldest -> newest
    func setTempTargets(_ value: [TempTarget]) {
        tempTargets.send(value)
    }

    /// MUST BE newest -> oldest
    func setGlucoseHistory(_ value: [BloodGlucose]) {
        glucoseHistory.send(value)
    }

    func sendNewGlucoseRecords(_ value: [BloodGlucose]) {
        newGlucoseRecords.send(value)
    }

    func sendGlucoseDeleted(_ value: [BloodGlucose]) {
        glucoseDeletions.send(value)
    }

    func setGlucoseAlarm(_ value: GlucoseAlarm?) {
        glucoseAlarm.send(value)
    }

    func sendBasalProfile(_ value: [BasalProfileEntry]) {
        basalProfileUpdates.send(value)
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
        alertMessages.send(value)
    }

    func sendAppBecomeActiveEvent() {
        appBecomeActiveEvents.send(())
    }

    func sendAlertUpdates(_ value: [AlertEntry]) {
        alertsUpdates.send(value)
    }
}
