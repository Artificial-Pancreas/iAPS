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

protocol DeviceDataManager {
    var availableCGMManagers: [CGMManagerDescriptor] { get }
    var pumpManager: PumpManagerUI? { get }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var bolusTrigger: PassthroughSubject<Bool, Never> { get }
    var manualTempBasal: PassthroughSubject<Bool, Never> { get }
    var errorSubject: PassthroughSubject<Error, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    var recommendsLoop: AnyPublisher<Void, Never> { get }

    // notify device manager when the app becomes active
    func didBecomeActive()

    func createBolusProgressReporter() -> DoseProgressReporter?

    func removePumpAsCGM()

    var alertHistoryStorage: AlertHistoryStorage! { get }

    var cgmManager: CGMManager? { get }

    var availablePumpManagers: [PumpManagerDescriptor] { get }

    func setupCGMManager(
        withIdentifier identifier: String,
        prefersToSkipUserInteraction: Bool
    ) -> Swift.Result<SetupUIResult<CGMManagerViewController, CGMManager>, Error>

    func cgmManagerSettingsView(cgmManager: CGMManagerUI) -> CGMManagerViewController
    func pumpManagerSettingsView(pumpManager: PumpManagerUI) -> PumpManagerViewController

    func setupPumpManager(
        withIdentifier identifier: String,
        initialSettings settings: PumpManagerSetupSettings,
        allowedInsulinTypes: [InsulinType],
        prefersToSkipUserInteraction: Bool
    ) -> Swift.Result<SetupUIResult<PumpManagerViewController, PumpManager>, Error>
}

private let accessLock = NSRecursiveLock(label: "BaseDeviceDataManager.accessLock")

private let staticCGMManagers: [CGMManagerDescriptor] = [
    CGMManagerDescriptor(identifier: MockCGMManager.pluginIdentifier, localizedTitle: MockCGMManager.localizedTitle),
    CGMManagerDescriptor(identifier: AppGroupCGM.pluginIdentifier, localizedTitle: AppGroupCGM.localizedTitle)
]

private let staticCGMManagersByIdentifier: [String: CGMManager.Type] = [
    MockCGMManager.pluginIdentifier: MockCGMManager.self,
    AppGroupCGM.pluginIdentifier: AppGroupCGM.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
    MockPumpManager.pluginIdentifier: MockPumpManager.self
]

private let availableStaticPumpManagers: [PumpManagerDescriptor] = [
    PumpManagerDescriptor(identifier: MockPumpManager.pluginIdentifier, localizedTitle: MockPumpManager.localizedTitle)
]

final class BaseDeviceDataManager: Injectable, DeviceDataManager {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseDeviceDataManager.processQueue")
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var bloodGlucoseManager: BloodGlucoseManager!
    @Injected() private var bluetoothProvider: BluetoothStateManager!
    @Injected() private var router: Router!

    @Injected() private var appCoordinator: AppCoordinator!

    private let _recommendsLoop = PassthroughSubject<Void, Never>()

    var recommendsLoop: AnyPublisher<Void, Never> {
        _recommendsLoop.eraseToAnyPublisher()
    }

    private var lifetime = Lifetime()

    private let pluginManager = PluginManager()

    private var displayGlucoseUnitObservers = WeakSynchronizedSet<DisplayGlucoseUnitObserver>()

    @Injected() private var displayGlucosePreference: DisplayGlucosePreference!

    @Persisted(key: "BaseDeviceDataManager.lastEventDate") var lastEventDate: Date? = nil

    let bolusTrigger = PassthroughSubject<Bool, Never>()
    let errorSubject = PassthroughSubject<Error, Never>()
    let manualTempBasal = PassthroughSubject<Bool, Never>()

    private var seenCGMDeviceId: String?

    @Published var cgmHasValidSensorSession: Bool = false

    var hasBLEHeartbeat: Bool {
        (pumpManager as? MockPumpManager) == nil
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("Pump")

    // MARK: - CGM

    private(set) var cgmManager: CGMManager? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            oldValue?.cgmManagerDelegate = nil
            oldValue?.delegateQueue = nil
            setupCGM()
            UserDefaults.standard.cgmManagerRawValue = cgmManager?.rawValue
        }
    }

    // MARK: - Pump

    private(set) var pumpManager: PumpManagerUI? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            oldValue?.pumpManagerDelegate = nil
            oldValue?.delegateQueue = nil

            // If the current CGMManager is a PumpManager, we clear it out.
            if cgmManager is PumpManagerUI {
                cgmManager = nil
            }

            setupPump()
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
        }
    }

    init(resolver: Resolver) {
        injectServices(resolver)

        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
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
            .sink { [weak self] _ in
                self?.heartbeat(forceRecommendLoop: true)
            }
            .store(in: &lifetime)

        //        TODO: [loopkit] is this correct? the notifyObserversOfDisplayGlucoseUnitChange part
        displayGlucosePreference.$unit
            .receive(on: DispatchQueue.main)
            .sink { unit in
                self.notifyObserversOfDisplayGlucoseUnitChange(to: unit)
            }
            .store(in: &lifetime)

        // from loop:
//        NotificationCenter.default.addObserver(forName: .HealthStorePreferredGlucoseUnitDidChange, object: healthStore, queue: nil) { [weak self] _ in
//            guard let self else {
//                return
//            }
//
//            Task { @MainActor in
//                if let unit = await self.healthStore.cachedPreferredUnits(for: .bloodGlucose) {
//                    self.displayGlucosePreference.unitDidChange(to: unit)
//                    self.notifyObserversOfDisplayGlucoseUnitChange(to: unit)
//                }
//            }
//        }
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
            case var .userInteractionRequired(viewController):
                viewController.pumpManagerOnboardingDelegate = self
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
            allowDebugFeatures: true,
            prefersToSkipUserInteraction: prefersToSkipUserInteraction,
            allowedInsulinTypes: allowedInsulinTypes
        )

        if case let .createdAndOnboarded(pumpManagerUI) = result {
            pumpManagerOnboarding(didCreatePumpManager: pumpManagerUI)
            pumpManagerOnboarding(didOnboardPumpManager: pumpManagerUI)
        }

        return .success(result)
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

    private func updatePumpData(completion: @escaping () -> Void) {
        guard let pumpManager = pumpManager, pumpManager.isOnboarded else {
            debug(.deviceManager, "Pump is not set, skip updating")
            completion()
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

                completion()
            }
        }
    }

    private func processCGMReadingResult(
        readingResult: CGMReadingResult,
        completion: @escaping ([BloodGlucose]) -> Void
    ) {
//        debug(.deviceManager, "Process CGM Reading Result launched")
        switch readingResult {
        case let .newData(values):
            var sessionStart: Date?
            if let cgmManager = cgmManager {
                sessionStart = KnownPlugins.sessionStart(cgmManager: cgmManager)
            }

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
                    sessionStartDate: sessionStart,
//                    transmitterID: transmitterID // TODO: do we need this? (for G6/G5)
                )
            }

            completion(bloodGlucose)
        case .unreliableData:
            // TODO: [loopkit] do something about unreliable readings?
            // loopManager.receivedUnreliableCGMReading()
            warning(.deviceManager, "CGM Manager - unreliable data")
            completion([])
        case .noData:
            completion([])
        case let .error(error):
            warning(
                .deviceManager,
                "CGM Manager - reading error: \(String(describing: error))"
            )
            errorSubject.send(error)
            completion([])
        }
        updatePumpManagerBLEHeartbeatPreference()
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        var availableCGMManagers = pluginManager.availableCGMManagers + staticCGMManagers
        if let pumpManagerAsCGMManager = pumpManager as? CGMManager {
            availableCGMManagers.append(CGMManagerDescriptor(
                identifier: pumpManagerAsCGMManager.pluginIdentifier,
                localizedTitle: pumpManagerAsCGMManager.localizedTitle
            ))
        }
        return availableCGMManagers
    }

    func setupCGMManager(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool = false) -> Swift
        .Result<SetupUIResult<CGMManagerViewController, CGMManager>, Error>
    {
        if let cgmManager = setupCGMManagerFromPumpManager(withIdentifier: identifier) {
            return .success(.createdAndOnboarded(cgmManager))
        }

        switch setupCGMManagerUI(withIdentifier: identifier, prefersToSkipUserInteraction: prefersToSkipUserInteraction) {
        case let .failure(error):
            return .failure(error)
        case let .success(success):
            switch success {
            case var .userInteractionRequired(viewController):
                viewController.cgmManagerOnboardingDelegate = self
                return .success(.userInteractionRequired(viewController))
            case let .createdAndOnboarded(cgmManagerUI):
                return .success(.createdAndOnboarded(cgmManagerUI))
            }
        }
    }

    func cgmManagerSettingsView(cgmManager: CGMManagerUI) -> CGMManagerViewController {
        var vc = cgmManager.settingsViewController(
            bluetoothProvider: bluetoothProvider,
            displayGlucosePreference: displayGlucosePreference,
            colorPalette: .default,
            allowDebugFeatures: true
        )
        vc.cgmManagerOnboardingDelegate = self
        return vc
    }

    func pumpManagerSettingsView(pumpManager: PumpManagerUI) -> PumpManagerViewController {
        var vc = pumpManager.settingsViewController(
            bluetoothProvider: bluetoothProvider,
            colorPalette: .default,
            allowDebugFeatures: true,
            allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
        )
        vc.pumpManagerOnboardingDelegate = self
        return vc
    }

    func removePumpAsCGM() {
        if cgmManager is PumpManagerUI, cgmManager?.pluginIdentifier == pumpManager?.pluginIdentifier {
            cgmManager = nil
        }
    }

    struct UnknownCGMManagerIdentifierError: Error {}

    fileprivate func setupCGMManagerUI(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool) -> Swift
        .Result<SetupUIResult<CGMManagerViewController, CGMManagerUI>, Error>
    {
        guard let cgmManagerUIType = cgmManagerTypeByIdentifier(identifier) else {
            return .failure(UnknownCGMManagerIdentifierError())
        }

        let result = cgmManagerUIType.setupViewController(
            bluetoothProvider: bluetoothProvider,
            displayGlucosePreference: displayGlucosePreference,
            colorPalette: .default,
            allowDebugFeatures: true,
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

    public func setupCGMManagerFromPumpManager(withIdentifier identifier: String) -> CGMManager? {
        guard identifier == pumpManager?.pluginIdentifier, let cgmManager = pumpManager as? CGMManager else {
            return nil
        }

        // We have a pump that is a CGM!
        self.cgmManager = cgmManager
        return cgmManager
    }

    private func cgmManagerTypeFromRawValue(_ rawValue: [String: Any]) -> CGMManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return cgmManagerTypeByIdentifier(managerIdentifier)
    }

    func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
              let Manager = cgmManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? CGMManagerUI
    }

    func createBolusProgressReporter() -> DoseProgressReporter? {
        pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
    }

    // MARK: loop

    private func heartbeat(forceRecommendLoop: Bool) {
        processQueue.safeSync {
            fetchNewDataFromCgm { readingResult in
                self.processCGMReadingResultAndLoop(readingResult: readingResult, forceRecommendLoop: forceRecommendLoop)
            }
        }
    }

    private func processCGMReadingResultAndLoop(readingResult: CGMReadingResult, forceRecommendLoop: Bool) {
        processQueue.safeSync {
            self.processCGMReadingResult(readingResult: readingResult) { bloodGlucose in
                self.processReceivedBloodGlucose(bloodGlucose: bloodGlucose, forceRecommendLoop: forceRecommendLoop)
            }
        }
    }

    private func processReceivedBloodGlucose(bloodGlucose: [BloodGlucose], forceRecommendLoop: Bool) {
        // storeNewBloodGlucose runs in queue.async with callback so that we don't block the CGM manager
        bloodGlucoseManager.storeNewBloodGlucose(bloodGlucose: bloodGlucose) { newGlucoseStored in
            if newGlucoseStored || forceRecommendLoop {
                self.processQueue.safeSync {
                    self.updatePumpData {
                        self._recommendsLoop.send(())
                    }
                }
            }
        }
    }

    private func fetchNewDataFromCgm(_ completion: @escaping (CGMReadingResult) -> Void) {
        guard let cgmManager = cgmManager else {
            completion(.noData)
            return
        }
        cgmManager.fetchNewDataIfNeeded(completion)
    }

    func refreshDeviceData() {
        processQueue.async {
            guard let pumpManager = self.pumpManager, pumpManager.isOnboarded else {
                return
            }
            self.updatePumpData {}
        }
    }
}

// MARK: - PumpManagerDelegate

extension BaseDeviceDataManager: PumpManagerDelegate {
    func pumpManagerPumpWasReplaced(_: PumpManager) {
        debug(.deviceManager, "pumpManagerPumpWasReplaced")
    }

    var detectedSystemTimeOffset: TimeInterval {
        // trustedTimeChecker.detectedSystemTimeOffset
        0
    }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "PumpManager \(pumpManager.pluginIdentifier) didAdjustPumpClockBy \(adjustment)")
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
        debug(.deviceManager, "PumpManager:\(String(describing: type(of: pumpManager))) did fire heartbeat")
        heartbeat(forceRecommendLoop: false)
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return pumpManagerMustProvideBLEHeartbeat
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

        // TODO: [loopkit] why is omnipod treated separately?
        if let omnipod = pumpManager as? OmnipodPumpManager {
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

        // TODO: [loopkit] why is omnible treated separately?
        if let omnipodBLE = pumpManager as? OmniBLEPumpManager {
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

        // TODO: [loopkit] from loop:
//        if status.deliveryIsUncertain != oldStatus.deliveryIsUncertain {
//            DispatchQueue.main.async {
//                if status.deliveryIsUncertain {
//                    self.deliveryUncertaintyAlertManager?.showAlert()
//                } else {
//                    self.deliveryUncertaintyAlertManager?.clearAlert()
//                }
//            }
//        }
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' will deactivate")

        DispatchQueue.main.async {
            self.pumpManager = nil
//            self.deliveryUncertaintyAlertManager = nil
//            self.settingsManager.storeSettings()
        }
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
//        dispatchPrecondition(condition: .onQueue(queue))
        debug(
            .deviceManager,
            "PumpManager:\(String(describing: type(of: pumpManager))) did update pumpRecordsBasalProfileStartEvents to \(String(describing: pumpRecordsBasalProfileStartEvents))"
        )

        // TODO: [loopkit] from loop:
//        doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
    }

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "error: \(error.localizedDescription), reason: \(String(describing: error.failureReason))")
        errorSubject.send(error)
    }

    func pumpManager(
        _: any LoopKit.PumpManager,
        hasNewPumpEvents events: [LoopKit.NewPumpEvent],
        lastReconciliation _: Date?,
        replacePendingEvents _: Bool,
        completion: @escaping ((any Error)?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump events:\n\(events.map(\.title).joined(separator: "\n"))")

        // TODO: [loopkit] is this filtering still needed?
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

    func pumpManager(
        _: any LoopKit.PumpManager,
        didRequestBasalRateScheduleChange _: LoopKit.BasalRateSchedule,
        completion: @escaping ((any Error)?) -> Void
    ) {
        // TODO: [loopkit] should we do anything here?
        // from loop:
        // saveUpdatedBasalRateSchedule(basalRateSchedule)
        completion(nil)
    }

    private var pumpManagerMustProvideBLEHeartbeat: Bool {
        /// Controls the management of the RileyLink timer tick, which is a reliably-changing BLE
        /// characteristic which can cause the app to wake. For most users, the G5 Transmitter and
        /// G4 Receiver are reliable as hearbeats, but users who find their resources extremely constrained
        /// due to greedy apps or older devices may choose to always enable the timer by always setting `true`
        !(cgmManager?.providesBLEHeartbeat == true)
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate?.addingTimeInterval(-15.minutes.timeInterval) ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }

    var automaticDosingEnabled: Bool {
        // TODO: [loopkit] does this affect anything?
        // none of the actual pump plugins seem to even read this var
        true
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: DeviceManagerDelegate {
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

    // TODO: [loopkit] this is commented out, fix or remove it?
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

extension BaseDeviceDataManager: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))

        // TODO: [loopkit] do we need to add -10 minutes? Does it do anything?
        return glucoseStorage.latestDate()
            .map { $0.addingTimeInterval(-10.minutes.timeInterval) } // additional time to calculate directions
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

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        // TODO: [loopkit] remove this debug log?
        debug(.deviceManager, "hasNew readingResult: \(readingResult)")
        processCGMReadingResultAndLoop(readingResult: readingResult, forceRecommendLoop: false)
    }

    func cgmManager(_: LoopKit.CGMManager, hasNew _: [PersistedCgmEvent]) {
        // TODO: [loopkit] implement this?
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        UserDefaults.standard.cgmManagerRawValue = manager.rawValue
        appCoordinator.setShouldUploadGlucose(manager.shouldSyncToRemoteService)
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate status: CGMManagerStatus) {
        DispatchQueue.main.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }
}

// MARK: - AlertPresenter

extension BaseDeviceDataManager: AlertObserver {
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

// MARK: - Plugins

extension BaseDeviceDataManager {
    func reportPluginInitializationComplete() {
        let allActivePlugins = self.allActivePlugins

        cgmManager?.initializationComplete(for: allActivePlugins)
        pumpManager?.initializationComplete(for: allActivePlugins)
    }

    var allActivePlugins: [Pluggable] {
        var allActivePlugins: [Pluggable] = []

        if let cgmManager = cgmManager {
            if !allActivePlugins.contains(where: { $0.pluginIdentifier == cgmManager.pluginIdentifier }) {
                allActivePlugins.append(cgmManager)
            }
        }

        if let pumpManager = pumpManager {
            if !allActivePlugins.contains(where: { $0.pluginIdentifier == pumpManager.pluginIdentifier }) {
                allActivePlugins.append(pumpManager)
            }
        }

        return allActivePlugins
    }
}

// MARK: - Client API

extension BaseDeviceDataManager {
    // TODO: [loopkit] should call this when app goes active?
    func didBecomeActive() {
        updatePumpManagerBLEHeartbeatPreference()
    }

    func updatePumpManagerBLEHeartbeatPreference() {
        pumpManager?.setMustProvideBLEHeartbeat(pumpManagerMustProvideBLEHeartbeat)
    }
}

// MARK: - CGMManagerOnboardingDelegate

extension BaseDeviceDataManager: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager cgmManager: CGMManagerUI) {
        debug(.deviceManager, "CGM manager with identifier '\(cgmManager.pluginIdentifier)' created")
        self.cgmManager = cgmManager
    }

    func cgmManagerOnboarding(didOnboardCGMManager cgmManager: CGMManagerUI) {
        precondition(cgmManager.isOnboarded)
        debug(.deviceManager, "CGM manager with identifier '\(cgmManager.pluginIdentifier)' onboarded")

        // TODO: [loopkit] is this correct?
        DispatchQueue.main.async {
            self.refreshDeviceData()
//            self.settingsManager.storeSettings()
        }
    }
}

// MARK: - PumpManagerOnboardingDelegate

extension BaseDeviceDataManager: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        debug(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' created")
        self.pumpManager = pumpManager
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        precondition(pumpManager.isOnboarded)
        debug(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' onboarded")

        DispatchQueue.main.async {
            self.refreshDeviceData()
        }
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {}
}

// MARK: - PersistedAlertStore

extension BaseDeviceDataManager: PersistedAlertStore {
    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion _: @escaping (Result<Bool, Error>) -> Void) {
        debug(.deviceManager, "doesIssueAlertExist")
        // TODO: [loopkit] from loop:
//        precondition(alertManager != nil)
//        alertManager.doesIssuedAlertExist(identifier: identifier, completion: completion)
    }

    func lookupAllUnretracted(managerIdentifier _: String, completion _: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        debug(.deviceManager, "lookupAllUnretracted")
        // TODO: [loopkit] from loop:
//        precondition(alertManager != nil)
//        alertManager.lookupAllUnretracted(managerIdentifier: managerIdentifier, completion: completion)
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion _: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        // TODO: [loopkit] from loop:
//        precondition(alertManager != nil)
//        alertManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier, completion: completion)
    }

    func recordRetractedAlert(_: Alert, at _: Date) {
        // TODO: [loopkit] implement this? from loop:
//        precondition(alertManager != nil)
//        alertManager.recordRetractedAlert(alert, at: date)
    }
}

private extension BaseDeviceDataManager {
    func setupCGM() {
        dispatchPrecondition(condition: .onQueue(.main))

        // TODO: [loopkit] is this the right way to detect a new sensor?
        // currently, the calibration service subscribes to this event to clear calibrations
        let previous = seenCGMDeviceId
        seenCGMDeviceId = cgmManager?.cgmManagerStatus.device?.localIdentifier
        if previous != nil, previous != seenCGMDeviceId {
            UserNotifications.NotificationCenter.default.post(name: .newSensorDetected, object: nil)
        }

        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = processQueue
        reportPluginInitializationComplete()

        updatePumpManagerBLEHeartbeatPreference()
        if let cgmManager = cgmManager {
            // TODO: [loopkit] alert manager
//            alertManager?.addAlertResponder(managerIdentifier: cgmManager.pluginIdentifier,
//                                            alertResponder: cgmManager)
            // TODO: [loopkit] alert manager
//            alertManager?.addAlertSoundVendor(managerIdentifier: cgmManager.pluginIdentifier,
//                                              soundVendor: cgmManager)
            cgmHasValidSensorSession = cgmManager.cgmManagerStatus.hasValidSensorSession
        } else {
            cgmHasValidSensorSession = false
        }

        appCoordinator.setShouldUploadGlucose(cgmManager?.shouldSyncToRemoteService ?? false)
        appCoordinator.setSensorDays(KnownPlugins.cgmExpirationByPluginIdentifier(cgmManager))
    }

    func setupPump() {
        dispatchPrecondition(condition: .onQueue(.main))

        pumpManager?.pumpManagerDelegate = self
        pumpManager?.delegateQueue = processQueue

        // TODO: [loopkit] do we need this?
        reportPluginInitializationComplete()

//        pumpManagerHUDProvider = pumpManager?.hudProvider(bluetoothProvider: bluetoothProvider, colorPalette: .default, allowedInsulinTypes: allowedInsulinTypes)

        // TODO: [loopkit] do we need this?
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
            pumpExpiresAtDate.send(KnownPlugins.pumpExpiration(pumpManager: pumpManager))
        } else {
            pumpDisplayState.value = nil
            pumpExpiresAtDate.send(nil)
            pumpName.send("")
        }
    }
}

extension BaseDeviceDataManager {
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
