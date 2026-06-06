import Combine
import Foundation
import LoopKit

final class AppCoordinator {
    //    @Published private(set) var shouldUploadGlucose: Bool = false
    //    @Published private(set) var sensorDays: Double? = nil
    //    @Published private(set) var pumpExpiresAtDate: Date? = nil
    //    @Published private(set) var isLooping = false
    //    @Published private(set) var pumpDisplayState: PumpDisplayState? = nil
    //    @Published private(set) var pumpManagerStatus: PumpManagerStatus? = nil
    //    @Published private(set) var pumpName = "Pump"
    //    @Published private(set) var alertNotAck = false
    //    @Published private(set) var lastLoopError: Error? = nil

    let pumpInfo = CurrentValueSubject<PumpDisplayInfo?, Never>(nil)

    let pumpStatus = CurrentValueSubject<PumpDisplayStatus?, Never>(nil)

    let cgmInfo = CurrentValueSubject<CgmDisplayInfo?, Never>(nil)

    let cgmStatus = CurrentValueSubject<CgmDisplayStatus?, Never>(nil)

    // -----

    let heartbeat = PassthroughSubject<Void, Never>()

    let isLooping = CurrentValueSubject<Bool, Never>(false)

    let recommendsLoop = PassthroughSubject<Void, Never>()

    let manualTempBasal = CurrentValueSubject<Bool, Never>(false)

    let pumpReservoir = CurrentValueSubject<Decimal?, Never>(nil)

    //    let pumpManagerStatus = CurrentValueSubject<PumpManagerStatus?, Never>(nil)

    //    let pumpIdentifier = CurrentValueSubject<String?, Never>(nil)

    //    let pumpIsCgm = CurrentValueSubject<Bool, Never>(false)

    //    let pumpOnboarded = CurrentValueSubject<Bool, Never>(false)

    //    let podStartTime = CurrentValueSubject<Date?, Never>(nil)

    //    let pumpExpirationDate = CurrentValueSubject<Date?, Never>(nil)

    //    let sensorDays = CurrentValueSubject<Double?, Never>(nil)

    //    let pumpBattery = CurrentValueSubject<Battery?, Never>(nil)

    //    let pumpName = CurrentValueSubject<String?, Never>(nil)

    //    let pumpTimeZone = CurrentValueSubject<TimeZone?, Never>(nil)

    let pumpNotifications = PassthroughSubject<AlertEntry, Never>()

    // TODO: this is never triggered?
    let pumpNotificationsRemove = PassthroughSubject<Void, Never>()

    let bolusInProgress = CurrentValueSubject<Bool, Never>(false)

    let deliveryUncertain = PassthroughSubject<Void, Never>()

    let deviceErrors = PassthroughSubject<Error, Never>()

    let alertNotAckUpdates = CurrentValueSubject<Bool, Never>(false)

    let loopCompleted = PassthroughSubject<Void, Never>()

    let pumpHistoryUpdates = PassthroughSubject<[PumpHistoryEvent], Never>()

    let glucoseHistoryUpdates = PassthroughSubject<[BloodGlucose], Never>()

    let suggestions = PassthroughSubject<Suggestion, Never>()

    let enactedSuggestions = PassthroughSubject<Suggestion, Never>()

    let newGlucoseRecords = PassthroughSubject<[BloodGlucose], Never>()

    let carbHistoryUpdates = PassthroughSubject<[CarbsEntry], Never>()

    let tempTargetsUpdates = PassthroughSubject<[TempTarget], Never>()

    let alertsUpdates = PassthroughSubject<[AlertEntry], Never>()

    let settingsUpdates = PassthroughSubject<FreeAPSSettings, Never>()

    let pumpSettingsUpdates = PassthroughSubject<PumpSettings, Never>()

    let preferencesUpdates = PassthroughSubject<Preferences, Never>()

    let basalProfileUpdates = PassthroughSubject<[BasalProfileEntry], Never>()

    let lastLoopDate = CurrentValueSubject<Date?, Never>(nil)

    let lastLoopError = CurrentValueSubject<Error?, Never>(nil)

    let bolusFailures = PassthroughSubject<Void, Never>()

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    let bolusAmount = CurrentValueSubject<Decimal?, Never>(nil)

    let pumpEvents = PassthroughSubject<[LoopKit.NewPumpEvent], Never>()

    let newSensorDetectedEvents = PassthroughSubject<Void, Never>()

    // --------------

    func setIsLooping(_ value: Bool) {
        isLooping.send(value)
    }

    func setPumpInfo(_ value: PumpDisplayInfo?) {
        pumpInfo.send(value)
    }

    func setPumpStatus(_ value: PumpDisplayStatus?) {
        pumpStatus.send(value)
    }

    func setPumpReservoir(_ value: Decimal?) {
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
        lastLoopError.send(value)
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
}
