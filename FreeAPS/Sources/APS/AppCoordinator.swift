import Combine
import Foundation
import LoopKit

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

    let isLooping = CurrentValueSubject<Bool, Never>(false)

    let recommendsLoop = PassthroughSubject<Void, Never>()

    let manualTempBasal = CurrentValueSubject<Bool, Never>(false)

    let pumpReservoir = CurrentValueSubject<ReservoirReading?, Never>(nil)

    let pumpNotifications = PassthroughSubject<AlertEntry, Never>()

    // TODO: this is never triggered?
    let pumpNotificationsRemove = PassthroughSubject<Void, Never>()

    let bolusInProgress = CurrentValueSubject<Bool, Never>(false)

    let deliveryUncertain = PassthroughSubject<Void, Never>()

    let deviceErrors = PassthroughSubject<Error, Never>()

    let alertNotAckUpdates = CurrentValueSubject<Bool, Never>(false)

    let loopCompleted = PassthroughSubject<Void, Never>()

    // pump events history updates, oldest -> newest
    let pumpHistoryUpdates = PassthroughSubject<[PumpHistoryEvent], Never>()

    let glucoseHistoryUpdates = PassthroughSubject<[BloodGlucose], Never>()

    let suggestions = PassthroughSubject<Suggestion, Never>()

    let enactedSuggestions = PassthroughSubject<Suggestion, Never>()

    let newGlucoseRecords = PassthroughSubject<[BloodGlucose], Never>()

    // carb events history updates, newest -> oldest
    let carbHistoryUpdates = PassthroughSubject<[CarbsEntry], Never>()

    let tempTargetsUpdates = PassthroughSubject<[TempTarget], Never>()

    let alertsUpdates = PassthroughSubject<[AlertEntry], Never>()

    let basalProfileUpdates = PassthroughSubject<[BasalProfileEntry], Never>()

    let lastLoopDate = CurrentValueSubject<Date?, Never>(nil)

    let lastLoopError = CurrentValueSubject<(error: Error, date: Date)?, Never>(nil)

    let bolusFailures = PassthroughSubject<Void, Never>()

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    let bolusAmount = CurrentValueSubject<Decimal?, Never>(nil)

    let pumpEvents = PassthroughSubject<[LoopKit.NewPumpEvent], Never>()

    let newSensorDetectedEvents = PassthroughSubject<Void, Never>()

    let liveActivitiesSystemEnabled = CurrentValueSubject<Bool, Never>(false)

    let alertMessages = PassthroughSubject<MessageContent, Never>()

    let appBecomeActiveEvents = PassthroughSubject<Void, Never>()

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

    func setPumpReservoir(_ value: ReservoirReading?) {
        pumpReservoir.send(value)
    }

    func setBolusInProgress(_ value: Bool) {
        bolusInProgress.send(value)
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

    func setLastLoopError(_ value: Error?) {
        if let value {
            lastLoopError.send((error: value, date: .now))
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

    func sendRecommendsLoop() {
        recommendsLoop.send(())
    }

    func sendPumpEvents(_ value: [LoopKit.NewPumpEvent]) {
        pumpEvents.send(value)
    }

    func setManualTempBasal(_ value: Bool) {
        manualTempBasal.send(value)
    }

    func sendSuggestion(_ value: Suggestion) {
        suggestions.send(value)
    }

    func sendEnactedSuggestion(_ value: Suggestion) {
        enactedSuggestions.send(value)
    }

    /// MUST BE ascending - oldest -> newest
    func sendPumpHistoryUpdate(_ value: [PumpHistoryEvent]) {
        pumpHistoryUpdates.send(value)
    }

    /// MUST BE descending - newest -> oldest
    func sendCarbHistoryUpdate(_ value: [CarbsEntry]) {
        carbHistoryUpdates.send(value)
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

    func sendLoopCompleted() {
        loopCompleted.send(())
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
}
