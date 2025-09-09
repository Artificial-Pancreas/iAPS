import Algorithms
import Combine
import DanaKit
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
@preconcurrency import MinimedKit
import MockKit
import OmniBLE
import OmniKit
import os.log
import ShareClient
import SwiftDate
import Swinject
import UserNotifications

// protocol DeviceDataManager {
//    var availableCGMManagers: [CGMManagerDescriptor] { get }
//    var pumpManager: PumpManagerUI? { get set }
//    var bluetoothManager: BluetoothStateManager { get }
//    var loopInProgress: Bool { get set }
//    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
//    var recommendsLoop: PassthroughSubject<Void, Never> { get }
//    var bolusTrigger: PassthroughSubject<Bool, Never> { get }
//    var manualTempBasal: PassthroughSubject<Bool, Never> { get }
//    var errorSubject: PassthroughSubject<Error, Never> { get }
//    var pumpName: CurrentValueSubject<String, Never> { get }
//    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
//
//    func heartbeat(date: Date)
//    func createBolusProgressReporter() -> DoseProgressReporter?
//    var alertHistoryStorage: AlertHistoryStorage! { get }
//
//    func cgmManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type?
//
//    var cgmManager: CGMManager? { get set }
//
//    func setupCGMManager(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool) -> Swift
//        .Result<SetupUIResult<CGMManagerViewController, CGMManager>, Error>
// }

// private let staticPumpManagers: [PumpManagerUI.Type] = [
//    MinimedPumpManager.self,
//    OmnipodPumpManager.self,
//    OmniBLEPumpManager.self,
//    DanaKitPumpManager.self,
//    MockPumpManager.self
// ]

// private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
//    MinimedPumpManager.pluginIdentifier: MinimedPumpManager.self,
//    OmnipodPumpManager.managerIdentifier: OmnipodPumpManager.self,
//    OmniBLEPumpManager.managerIdentifier: OmniBLEPumpManager.self,
//    DanaKitPumpManager.managerIdentifier: DanaKitPumpManager.self,
//    MockPumpManager.pluginIdentifier: MockPumpManager.self
// ]

// private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
//    map[Type.managerIdentifier] = Type
// }

private let accessLock = NSRecursiveLock(label: "DeviceDataManager.accessLock")

final class DeviceDataManager: Injectable {
    private let processQueue = DispatchQueue.markedQueue(label: "DeviceDataManager.processQueue")
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var bluetoothProvider: BluetoothStateManager!
    @Injected() private var router: Router!

    @Injected() private var appCoordinator: AppCoordinator!

    private var lifetime = Lifetime()

    private let pluginManager = PluginManager()

    private var displayGlucoseUnitObservers = WeakSynchronizedSet<DisplayGlucoseUnitObserver>()

    @Injected() private var displayGlucosePreference: DisplayGlucosePreference!

    @Persisted(key: "DeviceDataManager.lastEventDate") var lastEventDate: Date? = nil
    @SyncAccess(lock: accessLock) @Persisted(key: "DeviceDataManager.lastHeartBeatTime") var lastHeartBeatTime: Date =
        .distantPast

    // TODO: move to AppCoordinator (?)
    let bolusTrigger = PassthroughSubject<Bool, Never>()
    let errorSubject = PassthroughSubject<Error, Never>()
    let pumpNewStatus = PassthroughSubject<Void, Never>()
    let manualTempBasal = PassthroughSubject<Bool, Never>()

    @SyncAccess var loopInProgress: Bool = false

    @Published var cgmHasValidSensorSession: Bool = false

    private(set) var lastError: (date: Date, error: Error)?

    var bluetoothManager: BluetoothStateManager { bluetoothProvider }

    var hasBLEHeartbeat: Bool {
        (pumpManager as? MockPumpManager) == nil
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("Pump")

    init(resolver: Resolver) {
        injectServices(resolver)

        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
//            // Update lastPumpEventsReconciliation on DoseStore
//            if let lastSync = pumpManager?.lastSync {
//                doseStore.addPumpEvents([], lastReconciliation: lastSync) { _ in }
//            }
//            if let status = pumpManager?.status {
//                updatePumpIsAllowingAutomation(status: status)
//            }
        } else {
            pumpManager = nil
        }

        if let cgmManagerRawValue = UserDefaults.standard.cgmManagerRawValue {
            cgmManager = cgmManagerFromRawValue(cgmManagerRawValue)

            // Handle case of PumpManager providing CGM
            if cgmManager == nil, pumpManagerTypeFromRawValue(cgmManagerRawValue) != nil {
                cgmManager = pumpManager as? CGMManager
            }
        } else {
            cgmManager = nil
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        broadcaster.register(AlertObserver.self, observer: self)

        setupPump()
        setupCGM()

        appCoordinator.heartbeat
            .sink { [weak self] date in
                self?.heartbeat(date: date)
            }
            .store(in: &lifetime)
    }

    private(set) var cgmManager: CGMManager? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            setupCGM()

//            if cgmManager?.pluginIdentifier != oldValue?.pluginIdentifier {
//                if let cgmManager = cgmManager {
//                    analyticsServicesManager.cgmWasAdded(identifier: cgmManager.pluginIdentifier)
//                } else {
//                    analyticsServicesManager.cgmWasRemoved()
//                }
//            }
//            NotificationCenter.default.post(name: .CGMManagerChanged, object: self, userInfo: nil)
            UserDefaults.standard.cgmManagerRawValue = cgmManager?.rawValue
        }
    }

    struct UnknownCGMManagerIdentifierError: Error {}

    func setupCGMManager(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool = false) -> Swift
        .Result<SetupUIResult<CGMManagerViewController, CGMManager>, Error>
    {
        switch setupCGMManagerUI(withIdentifier: identifier, prefersToSkipUserInteraction: prefersToSkipUserInteraction) {
        case let .failure(error):
            return .failure(error)
        case let .success(success):
            switch success {
            case let .userInteractionRequired(viewController):
                return .success(.userInteractionRequired(viewController))
            case let .createdAndOnboarded(cgmManagerUI):
                return .success(.createdAndOnboarded(cgmManagerUI))
            }
        }
    }

    func setupCGMManagerUI(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool) -> Swift
        .Result<SetupUIResult<CGMManagerViewController, CGMManagerUI>, Error>
    {
        guard let cgmManagerUIType = cgmManagerTypeByIdentifier(identifier) else {
            return .failure(UnknownCGMManagerIdentifierError())
        }

        let result = cgmManagerUIType.setupViewController(
            bluetoothProvider: bluetoothProvider,
            displayGlucosePreference: displayGlucosePreference,
            colorPalette: .default,
            allowDebugFeatures: false,
            prefersToSkipUserInteraction: prefersToSkipUserInteraction
        )

        if case let .createdAndOnboarded(cgmManagerUI) = result {
            cgmManagerOnboarding(didCreateCGMManager: cgmManagerUI)
            cgmManagerOnboarding(didOnboardCGMManager: cgmManagerUI)
        }

        return .success(result)
    }

    func cgmManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        pluginManager.getCGMManagerTypeByIdentifier(identifier) ?? staticCGMManagersByIdentifier[identifier] as? CGMManagerUI.Type
    }

    func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
              let Manager = cgmManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? CGMManagerUI
    }

    private func cgmManagerTypeFromRawValue(_ rawValue: [String: Any]) -> CGMManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }
        return cgmManagerTypeByIdentifier(managerIdentifier)
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        var availableCGMManagers = pluginManager.availableCGMManagers + availableStaticCGMManagers
        if let pumpManagerAsCGMManager = pumpManager as? CGMManager {
            availableCGMManagers.append(CGMManagerDescriptor(
                identifier: pumpManagerAsCGMManager.pluginIdentifier,
                localizedTitle: pumpManagerAsCGMManager.localizedTitle
            ))
        }

        availableCGMManagers = availableCGMManagers.filter({ _ in
//            guard !deviceWhitelist.cgmDevices.isEmpty else {
            true
//            }

//            return deviceWhitelist.cgmDevices.contains(cgmManager.identifier)
        })

        return availableCGMManagers
    }

    var availablePumpManagers: [PumpManagerDescriptor] {
        var pumpManagers = pluginManager.availablePumpManagers + availableStaticPumpManagers

        pumpManagers = pumpManagers.filter({ _ in
//            guard !deviceWhitelist.pumpDevices.isEmpty else {
            true
//            }

//            return deviceWhitelist.pumpDevices.contains(pumpManager.identifier)
        })

        return pumpManagers
    }

    func setupPumpManager(
        withIdentifier identifier: String,
        initialSettings settings: PumpManagerSetupSettings,
        allowedInsulinTypes: [InsulinType],
        prefersToSkipUserInteraction: Bool
    ) -> Swift.Result<SetupUIResult<PumpManagerViewController, PumpManager>, Error> {
        switch setupPumpManagerUI(
            withIdentifier: identifier,
            initialSettings: settings,
            allowedInsulinTypes: allowedInsulinTypes,
            prefersToSkipUserInteraction: prefersToSkipUserInteraction
        ) {
        case let .failure(error):
            return .failure(error)
        case let .success(success):
            switch success {
            case let .userInteractionRequired(viewController):
                return .success(.userInteractionRequired(viewController))
            case let .createdAndOnboarded(pumpManagerUI):
                return .success(.createdAndOnboarded(pumpManagerUI))
            }
        }
    }

    struct UnknownPumpManagerIdentifierError: Error {}

    func setupPumpManagerUI(
        withIdentifier identifier: String,
        initialSettings settings: PumpManagerSetupSettings,
        allowedInsulinTypes: [InsulinType],
        prefersToSkipUserInteraction: Bool = false
    ) -> Swift.Result<SetupUIResult<PumpManagerViewController, PumpManagerUI>, Error> {
        guard let pumpManagerUIType = pumpManagerTypeByIdentifier(identifier) else {
            return .failure(UnknownPumpManagerIdentifierError())
        }

        let result = pumpManagerUIType.setupViewController(
            initialSettings: settings,
            bluetoothProvider: bluetoothProvider,
            colorPalette: .default,
            // TODO: [loopkit] fix this
            allowDebugFeatures: true,
//            allowDebugFeatures: FeatureFlags.allowDebugFeatures,
            prefersToSkipUserInteraction: prefersToSkipUserInteraction,
            allowedInsulinTypes: allowedInsulinTypes
        )

        if case let .createdAndOnboarded(pumpManagerUI) = result {
            pumpManagerOnboarding(didCreatePumpManager: pumpManagerUI)
            pumpManagerOnboarding(didOnboardPumpManager: pumpManagerUI)
        }

        return .success(result)
    }

    private(set) var pumpManager: PumpManagerUI? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))

            // If the current CGMManager is a PumpManager, we clear it out.
            if cgmManager is PumpManagerUI {
                cgmManager = nil
            }

            setupPump()
//            NotificationCenter.default.post(name: .PumpManagerChanged, object: self, userInfo: nil)
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
        }
    }

    func createBolusProgressReporter() -> DoseProgressReporter? {
        pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
    }

    private func heartbeat(date: Date) {
//        TODO: [loopkit] this check is skipped in updatePumpData, is it okay to skip here as well?
//        directly in loop() function
//        guard !loopInProgress else {
//            warning(.deviceManager, "Loop in progress. Skip updating.")
//            return
//        }
        processQueue.safeSync {
            lastHeartBeatTime = date
            updatePumpData()
        }
    }

    private func refreshCGM(_ completion: (() -> Void)? = nil) {
        guard let cgmManager = cgmManager else {
            completion?()
            return
        }

        cgmManager.fetchNewDataIfNeeded { result in
            self.processQueue.async {
                self.processCGMReadingResult(cgmManager, readingResult: result) {
//                    if self.loopManager.lastLoopCompleted == nil || self.loopManager.lastLoopCompleted!.timeIntervalSinceNow < -.minutes(4.2) {
//                        self.log.default("Triggering Loop from refreshCGM()")
//                        self.checkPumpDataAndLoop()
//                    }
                    completion?()
                }
            }
        }
    }

    private func updatePumpData() {
        guard let pumpManager = pumpManager, pumpManager.isOnboarded else {
            debug(.deviceManager, "Pump is not set, skip updating")
            return
        }

        debug(.deviceManager, "Start updating the pump data")
        processQueue.safeSync {
            pumpManager.ensureCurrentPumpData { _ in
                debug(.deviceManager, "Pump data updated.")
                // directly in loop() function
                //        guard !loopInProgress else {
                //            warning(.deviceManager, "Loop already in progress. Skip recommendation.")
                //            return
                //        }
                self.appCoordinator.sendRecommendsLoop()
            }
        }
    }

    public func pumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        pluginManager.getPumpManagerTypeByIdentifier(identifier) ?? staticPumpManagersByIdentifier[identifier]
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return pumpManagerTypeByIdentifier(managerIdentifier)
    }

    func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    func refreshDeviceData() {
        refreshCGM {
            self.updatePumpData()
        }
    }
}

private extension DeviceDataManager {
    func setupCGM() {
        dispatchPrecondition(condition: .onQueue(.main))

        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = processQueue
//        reportPluginInitializationComplete()

//        glucoseStore.managedDataInterval = cgmManager?.managedDataInterval
//        glucoseStore.healthKitStorageDelay = cgmManager.map{ type(of: $0).healthKitStorageDelay } ?? 0

        updatePumpManagerBLEHeartbeatPreference()
        if let cgmManager = cgmManager {
            // TODO: [loopkit] alert manager
//            alertManager?.addAlertResponder(managerIdentifier: cgmManager.pluginIdentifier,
//                                            alertResponder: cgmManager)
            // TODO: [loopkit] alert manager
//            alertManager?.addAlertSoundVendor(managerIdentifier: cgmManager.pluginIdentifier,
//                                              soundVendor: cgmManager)
            cgmHasValidSensorSession = cgmManager.cgmManagerStatus.hasValidSensorSession

//            analyticsServicesManager.identifyCGMType(cgmManager.pluginIdentifier)
        }

        if let cgmManagerUI = cgmManager as? CGMManagerUI {
            addDisplayGlucoseUnitObserver(cgmManagerUI)
            appCoordinator.setShouldUploadGlucose(cgmManagerUI.shouldSyncToRemoteService)
        } else {
            appCoordinator.setShouldUploadGlucose(false)
        }
    }

    func setupPump() {
        dispatchPrecondition(condition: .onQueue(.main))

        pumpManager?.pumpManagerDelegate = self
        pumpManager?.delegateQueue = processQueue
//        reportPluginInitializationComplete()

//        doseStore.device = pumpManager?.status.device
//        pumpManagerHUDProvider = pumpManager?.hudProvider(bluetoothProvider: bluetoothProvider, colorPalette: .default, allowedInsulinTypes: allowedInsulinTypes)

        // Proliferate PumpModel preferences to DoseStore
//        if let pumpRecordsBasalProfileStartEvents = pumpManager?.pumpRecordsBasalProfileStartEvents {
//            doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
//        }
        if let pumpManager = pumpManager {
            // TODO: [loopkit] alert manager
//            alertManager?.addAlertResponder(managerIdentifier: pumpManager.pluginIdentifier,
//                                                  alertResponder: pumpManager)
            // TODO: [loopkit] alert manager
//            alertManager?.addAlertSoundVendor(managerIdentifier: pumpManager.pluginIdentifier,
//                                                    soundVendor: pumpManager)
            // TODO: [loopkit] uncertainty alert manager
//            deliveryUncertaintyAlertManager = DeliveryUncertaintyAlertManager(pumpManager: pumpManager, alertPresenter: alertPresenter)

            updatePumpManagerBLEHeartbeatPreference()

            pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
            pumpName.send(pumpManager.localizedTitle)

            // TODO: [loopkit] is there a generic way to get the expiration date?
            if let omnipod = pumpManager as? OmnipodPumpManager {
                guard let endTime = omnipod.state.podState?.expiresAt else {
                    pumpExpiresAtDate.send(nil)
                    return
                }
                pumpExpiresAtDate.send(endTime)
            }
            if let omnipodBLE = pumpManager as? OmniBLEPumpManager {
                guard let endTime = omnipodBLE.state.podState?.expiresAt else {
                    pumpExpiresAtDate.send(nil)
                    return
                }
                pumpExpiresAtDate.send(endTime)
            }
        } else {
            pumpDisplayState.value = nil
            pumpExpiresAtDate.send(nil)
            pumpName.send("")
        }
    }

    func setLastError(error: Error) {
        DispatchQueue.main.async {
            self.lastError = (date: Date(), error: error)
        }
    }
}

extension DeviceDataManager {
    func addDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        let queue = DispatchQueue.main
        displayGlucoseUnitObservers.insert(observer, queue: queue)
        queue.async {
            observer.unitDidChange(to: self.displayGlucosePreference.unit)
        }
    }

    func removeDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        displayGlucoseUnitObservers.removeElement(observer)
    }

    func notifyObserversOfDisplayGlucoseUnitChange(to displayGlucoseUnit: HKUnit) {
        displayGlucoseUnitObservers.forEach {
            $0.unitDidChange(to: displayGlucoseUnit)
        }
    }
}

// MARK: - Client API

extension DeviceDataManager {
//    func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (_ error: Error?) -> Void = { _ in }) {
//        guard let pumpManager = pumpManager else {
//            completion(LoopError.configurationError(.pumpManager))
//            return
//        }
//
//        self.loopManager.addRequestedBolus(DoseEntry(type: .bolus, startDate: Date(), value: units, unit: .units, isMutable: true)) {
//            pumpManager.enactBolus(units: units, activationType: activationType) { (error) in
//                if let error = error {
//                    self.log.error("%{public}@", String(describing: error))
//                    switch error {
//                    case .uncertainDelivery:
//                        // Do not generate notification on uncertain delivery error
//                        break
//                    default:
//                        // Do not generate notifications for automatic boluses that fail.
//                        if !activationType.isAutomatic {
//                            NotificationManager.sendBolusFailureNotification(for: error, units: units, at: Date(), activationType: activationType)
//                        }
//                    }
//
//                    self.loopManager.bolusRequestFailed(error) {
//                        completion(error)
//                    }
//                } else {
//                    self.loopManager.bolusConfirmed() {
//                        completion(nil)
//                    }
//                }
//            }
//            // Trigger forecast/recommendation update for remote clients
//            self.loopManager.updateRemoteRecommendation()
//        }
//    }

//    func enactBolus(units: Double, activationType: BolusActivationType) async throws {
//        return try await withCheckedThrowingContinuation { continuation in
//            enactBolus(units: units, activationType: activationType) { error in
//                if let error = error {
//                    continuation.resume(throwing: error)
//                    return
//                }
//                continuation.resume()
//            }
//        }
//    }

    var pumpManagerStatus: PumpManagerStatus? {
        pumpManager?.status
    }

    var cgmManagerStatus: CGMManagerStatus? {
        cgmManager?.cgmManagerStatus
    }

    func didBecomeActive() {
        updatePumpManagerBLEHeartbeatPreference()
    }

    func updatePumpManagerBLEHeartbeatPreference() {
        pumpManager?.setMustProvideBLEHeartbeat(pumpManagerMustProvideBLEHeartbeat)
    }
}

extension DeviceDataManager: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager cgmManager: CGMManagerUI) {
        info(.deviceManager, "CGM manager with identifier '\(cgmManager.pluginIdentifier)' created")
        self.cgmManager = cgmManager
    }

    func cgmManagerOnboarding(didOnboardCGMManager cgmManager: CGMManagerUI) {
        precondition(cgmManager.isOnboarded)
        info(.deviceManager, "CGM manager with identifier '\(cgmManager.pluginIdentifier)' onboarded")

        // TODO: [loopkit] is this correct?
//        DispatchQueue.main.async {
        refreshDeviceData()
//            self.settingsManager.storeSettings()
//        }
    }
}

// MARK: - PumpManagerDelegate

extension DeviceDataManager: PumpManagerDelegate {
    func pumpManager(
        _: any LoopKit.PumpManager,
        didRequestBasalRateScheduleChange _: LoopKit.BasalRateSchedule,
        completion _: @escaping ((any Error)?) -> Void
    ) {}

    var automaticDosingEnabled: Bool {
        // TODO: [loopkit] fix this
        true
    }

    func pumpManagerPumpWasReplaced(_: PumpManager) {
        debug(.deviceManager, "pumpManagerPumpWasReplaced")
    }

    var detectedSystemTimeOffset: TimeInterval {
        // trustedTimeChecker.detectedSystemTimeOffset
        0
    }

    func pumpManager(_: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "didAdjustPumpClockBy \(adjustment)")
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
        if self.pumpManager == nil, let newPumpManager = pumpManager as? PumpManagerUI {
            self.pumpManager = newPumpManager
        }
        pumpName.send(pumpManager.localizedTitle)
    }

    /// heartbeat with pump occurs some issues in the backgroundtask - so never used
    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        // TODO: [loopkit] is this correct?
        info(.deviceManager, "PumpManager:\(String(describing: type(of: pumpManager))) did fire heartbeat")
        refreshCGM()
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return pumpManagerMustProvideBLEHeartbeat
    }

    private var pumpManagerMustProvideBLEHeartbeat: Bool {
        /// Controls the management of the RileyLink timer tick, which is a reliably-changing BLE
        /// characteristic which can cause the app to wake. For most users, the G5 Transmitter and
        /// G4 Receiver are reliable as hearbeats, but users who find their resources extremely constrained
        /// due to greedy apps or older devices may choose to always enable the timer by always setting `true`
        !(cgmManager?.providesBLEHeartbeat == true)
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")

        if case .inProgress = status.bolusState {
            bolusTrigger.send(true)
        } else {
            bolusTrigger.send(false)
        }

        if status.insulinType != oldStatus.insulinType {
            settingsManager.updateInsulinCurve(status.insulinType)
        }

        let batteryPercent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: batteryPercent,
            voltage: nil,
            string: batteryPercent >= 10 ? .normal : .low,
            display: pumpManager.status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
        broadcaster.notify(PumpBatteryObserver.self, on: processQueue) {
            $0.pumpBatteryDidChange(battery)
        }
        broadcaster.notify(PumpTimeZoneObserver.self, on: processQueue) {
            $0.pumpTimeZoneDidChange(status.timeZone)
        }

        if let omnipod = pumpManager as? OmnipodPumpManager {
            let reservoirVal = omnipod.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF
            // TODO: find the value Pod.maximumReservoirReading
            let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal

            storage.save(Decimal(reservoir), as: OpenAPS.Monitor.reservoir)
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(reservoir))
            }

            if let tempBasal = omnipod.state.podState?.unfinalizedTempBasal, !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                // the manual basal temp is launch - block every thing
                debug(.deviceManager, "manual temp basal")
                manualTempBasal.send(true)
            } else {
                // no more manual Temp Basal !
                manualTempBasal.send(false)
            }

            guard let endTime = omnipod.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)

            if let startTime = omnipod.state.podState?.activatedAt {
                storage.save(startTime, as: OpenAPS.Monitor.podAge)
            }
        }

        if let omnipodBLE = pumpManager as? OmniBLEPumpManager {
            let reservoirVal = omnipodBLE.state.podState?.lastInsulinMeasurements?.reservoirLevel ?? 0xDEAD_BEEF
            // TODO: find the value Pod.maximumReservoirReading
            let reservoir = Decimal(reservoirVal) > 50.0 ? 0xDEAD_BEEF : reservoirVal

            storage.save(Decimal(reservoir), as: OpenAPS.Monitor.reservoir)
            broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
                $0.pumpReservoirDidChange(Decimal(reservoir))
            }

            // manual temp basal on
            if let tempBasal = omnipodBLE.state.podState?.unfinalizedTempBasal, !tempBasal.isFinished(),
               !tempBasal.automatic
            {
                // the manual basal temp is launch - block every thing
                debug(.deviceManager, "manual temp basal")
                manualTempBasal.send(true)
            } else {
                // no more manual Temp Basal !
                manualTempBasal.send(false)
            }

            guard let endTime = omnipodBLE.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)

            if let startTime = omnipodBLE.state.podState?.activatedAt {
                storage.save(startTime, as: OpenAPS.Monitor.podAge)
            }
        }
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        info(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' will deactivate")

        DispatchQueue.main.async {
            self.pumpManager = nil
//            self.deliveryUncertaintyAlertManager = nil
//            self.settingsManager.storeSettings()
        }
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "error: \(error.localizedDescription), reason: \(String(describing: error.failureReason))")
        errorSubject.send(error)
    }

    func pumpManager(
        _: any LoopKit.PumpManager,
        hasNewPumpEvents events: [LoopKit.NewPumpEvent],
        lastReconciliation _: Date?,
        replacePendingEvents _: Bool, // TODO: this is new
        completion: @escaping ((any Error)?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump events:\n\(events.map(\.title).joined(separator: "\n"))")

        // filter buggy TBRs > maxBasal from MDT
        let events = events.filter {
            // type is optional...
            guard let type = $0.type, type == .tempBasal else { return true }
            return $0.dose?.unitsPerHour ?? 0 <= Double(settingsManager.pumpSettings.maxBasal)
        }
        pumpHistoryStorage.storePumpEvents(events)
        lastEventDate = events.last?.date
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Reservoir Value \(units), at: \(date)")
        storage.save(Decimal(units), as: OpenAPS.Monitor.reservoir)
        broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
            $0.pumpReservoirDidChange(Decimal(units))
        }

        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate?.addingTimeInterval(-15.minutes.timeInterval) ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension DeviceDataManager: DeviceManagerDelegate {
    func issueAlert(_ alert: Alert) {
        alertHistoryStorage.storeAlert(
            AlertEntry(
                alertIdentifier: alert.identifier.alertIdentifier,
                primitiveInterruptionLevel: alert.interruptionLevel.storedValue as? Decimal,
                issuedDate: Date(),
                managerIdentifier: alert.identifier.managerIdentifier,
                triggerType: alert.trigger.storedType,
                triggerInterval: alert.trigger.storedInterval as? Decimal,
                contentTitle: alert.foregroundContent?.title,
                contentBody: alert.foregroundContent?.body
            )
        )
    }

    func retractAlert(identifier: Alert.Identifier) {
        alertHistoryStorage.deleteAlert(identifier: identifier.alertIdentifier)
    }

    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion _: @escaping (Result<Bool, Error>) -> Void) {
        debug(.deviceManager, "doesIssueAlertExist")
    }

    func lookupAllUnretracted(managerIdentifier _: String, completion _: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        debug(.deviceManager, "lookupAllUnretracted")
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {}

    func recordRetractedAlert(_: Alert, at _: Date) {}

    //    func scheduleNotification(
    //        for _: DeviceManager,
    //        identifier: String,
    //        content: UNNotificationContent,
    //        trigger: UNNotificationTrigger?
    //    ) {
    //        let request = UNNotificationRequest(
    //            identifier: identifier,
    //            content: content,
    //            trigger: trigger
    //        )
    //
    //        DispatchQueue.main.async {
    //            UNUserNotificationCenter.current().add(request)
    //        }
    //    }
    //
    //    func clearNotification(for _: DeviceManager, identifier: String) {
    //        DispatchQueue.main.async {
    //            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    //        }
    //    }

    func removeNotificationRequests(for _: DeviceManager, identifiers: [String]) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deviceManager(
        _: LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type _: LoopKit.DeviceLogEntryType,
        message: String,
        completion _: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "device Manager for \(String(describing: deviceIdentifier)) : \(message)")
    }
}

// MARK: - CGMManagerDelegate

extension DeviceDataManager: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))

        // TODO: [loopkit] in the FetchGlucoseManager it was this:
        // return glucoseStorage.lastGlucoseDate()

        return glucoseStorage.syncDate().addingTimeInterval(-10.minutes.timeInterval) // additional time to calculate directions
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        // TODO: [loopkit] verify this
        dispatchPrecondition(condition: .onQueue(processQueue))
        UserDefaults.standard.cgmManagerRawValue = manager.rawValue
        appCoordinator.setShouldUploadGlucose(manager.shouldSyncToRemoteService)
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // TODO: [loopkit] should it be unique?
        // return string unique to this instance of the CGMManager
        UUID().uuidString
        // return "DeviceDataManager"
    }

    func cgmManager(_: any LoopKit.CGMManager, hasNew _: [LoopKit.PersistedCgmEvent]) {
        // TODO: [loopkit] implement this?
    }

    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "CGM Manager with identifier \(manager.pluginIdentifier) wants deletion")
        DispatchQueue.main.async {
            if let cgmManagerUI = self.cgmManager as? CGMManagerUI {
                self.removeDisplayGlucoseUnitObserver(cgmManagerUI)
            }
            self.cgmManager = nil
            self.displayGlucoseUnitObservers.cleanupDeallocatedElements()
//            self.settingsManager.storeSettings()
        }
    }

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        processCGMReadingResult(manager, readingResult: readingResult) {
//            debug(.deviceManager, "\(manager.pluginIdentifier) - Direct return done")
        }
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        DispatchQueue.main.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }

    private func processCGMReadingResult(
        _ manager: CGMManager,
        readingResult: CGMReadingResult,
        completion: @escaping () -> Void
    ) {
//        debug(.deviceManager, "Process CGM Reading Result launched")
        switch readingResult {
        case let .newData(values):

//            var activationDate: Date = .distantPast
//            var sessionStart: Date = .distantPast
//            if let cgmG7Manager = cgmManager as? G7CGMManager {
//                activationDate = cgmG7Manager.sensorActivatedAt ?? .distantPast
//                sessionStart = cgmG7Manager.sensorFinishesWarmupAt ?? .distantPast
//                print("Activastion date: " + activationDate.description)
//            }

            let bloodGlucose = values.map { newGlucoseSample -> BloodGlucose in
                let quantity = newGlucoseSample.quantity
                let value = Int(quantity.doubleValue(for: .milligramsPerDeciliter))
                return BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: value,
                    direction: .init(trendType: newGlucoseSample.trend),
                    date: Decimal(Int(newGlucoseSample.date.timeIntervalSince1970 * 1000)),
                    dateString: newGlucoseSample.date,
                    unfiltered: Decimal(value),
                    filtered: nil,
                    noise: nil,
                    glucose: value,
                    type: "sgv",
//                    activationDate: activationDate,
//                    sessionStartDate: sessionStart
                )
            }

            appCoordinator.sendBloodGlucose(bloodGlucose: bloodGlucose)
            completion()
        case .unreliableData:
            // loopManager.receivedUnreliableCGMReading()
            warning(.deviceManager, "CGM Manager with identifier \(manager.pluginIdentifier) unreliable data")
            completion()
        case .noData:
            completion()
        case let .error(error):
            warning(
                .deviceManager,
                "CGM Manager with identifier \(manager.pluginIdentifier) reading error: \(String(describing: error))"
            )
            setLastError(error: error)
            completion()
        }
    }
}

// MARK: - AlertPresenter

extension DeviceDataManager: AlertObserver {
    func AlertDidUpdate(_ alerts: [AlertEntry]) {
        alerts.forEach { alert in
            if alert.acknowledgedDate == nil {
                ackAlert(alert: alert)
            }
        }
    }

    private func ackAlert(alert: AlertEntry) {
        let typeMessage: MessageType
        let alertUp = alert.alertIdentifier.uppercased()
        if alertUp.contains("FAULT") || alertUp.contains("ERROR") {
            typeMessage = .errorPump
        } else {
            typeMessage = .warning
        }

        let messageCont = MessageContent(content: alert.contentBody ?? "Unknown", type: typeMessage)
        let alertIssueDate = alert.issuedDate

        processQueue.async {
            // if not alert in OmniPod/BLE, the acknowledgeAlert didn't do callbacks- Hack to manage this case
            if let omnipodBLE = self.pumpManager as? OmniBLEPumpManager {
                if omnipodBLE.state.activeAlerts.isEmpty {
                    // force to ack alert in the alertStorage
                    self.alertHistoryStorage.ackAlert(alertIssueDate, nil)
                }
            }

            if let omniPod = self.pumpManager as? OmnipodPumpManager {
                if omniPod.state.activeAlerts.isEmpty {
                    // force to ack alert in the alertStorage
                    self.alertHistoryStorage.ackAlert(alertIssueDate, nil)
                }
            }

            self.pumpManager?.acknowledgeAlert(alertIdentifier: alert.alertIdentifier) { error in
                self.router.alertMessage.send(messageCont)
                if let error = error {
                    self.alertHistoryStorage.ackAlert(alertIssueDate, error.localizedDescription)
                    debug(.deviceManager, "acknowledge not succeeded with error \(error.localizedDescription)")
                } else {
                    self.alertHistoryStorage.ackAlert(alertIssueDate, nil)
                }
            }

            self.broadcaster.notify(pumpNotificationObserver.self, on: self.processQueue) {
                $0.pumpNotification(alert: alert)
            }
        }
    }
}

// MARK: - PumpManagerOnboardingDelegate

extension DeviceDataManager: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        info(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' created")
        self.pumpManager = pumpManager
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        precondition(pumpManager.isOnboarded)
        info(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' onboarded")

        DispatchQueue.main.async {
            self.refreshDeviceData()
//            self.settingsManager.storeSettings()
        }
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {}
}

// extension DeviceDataManager: AlertPresenter {
//    func issueAlert(_: Alert) {}
//    func retractAlert(identifier _: Alert.Identifier) {}
// }

// MARK: Others

protocol PumpReservoirObserver {
    func pumpReservoirDidChange(_ reservoir: Decimal)
}

protocol PumpBatteryObserver {
    func pumpBatteryDidChange(_ battery: Battery)
}

protocol PumpTimeZoneObserver {
    func pumpTimeZoneDidChange(_ timezone: TimeZone)
}
