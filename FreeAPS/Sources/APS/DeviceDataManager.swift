import Algorithms
import AsyncAlgorithms
import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import MockKit
import MockKitUI
import os.log
import SwiftDate
import Swinject
import UserNotifications

protocol DeviceDataManager: Sendable {
    var availableCGMManagers: [CGMManagerDescriptor] { get }
    var availablePumpManagers: [PumpManagerDescriptor] { get }

    func cgmInfo() -> GlucoseSourceInfo?

    func createBolusProgressReporter() -> DoseProgressReporter?

    func removePumpAsCGM()

    @MainActor func setupCGMManager(
        withIdentifier identifier: String,
        prefersToSkipUserInteraction: Bool
    ) -> Swift.Result<SetupUIResult<CGMManagerViewController, CGMManager>, Error>

    @MainActor func setupPumpManager(
        withIdentifier identifier: String,
        initialSettings settings: PumpManagerSetupSettings,
        allowedInsulinTypes: [InsulinType],
        prefersToSkipUserInteraction: Bool
    ) -> Swift.Result<SetupUIResult<PumpManagerViewController, PumpManager>, Error>

    @MainActor func cgmManagerSettingsView() -> CGMManagerViewController?
    @MainActor func pumpManagerSettingsView() -> PumpManagerViewController?

    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) async throws

    func enactBolus(units: Double, automatic: Bool) async throws

    func cancelBolus() async throws -> DoseEntry?

    func suspendDelivery() async throws

    func resumeDelivery() async throws

    // this information is available from app coordinator, but when verifying the pump status before executing pump commands it's better to ask the pump manager
    func currentPumpStatus() -> PumpDisplayStatus?

    func roundBolus(amount: Decimal, maxBolus: Decimal) -> Decimal

    func roundToSupportedBolusVolume(units: Double) throws -> Double

    func roundToSupportedBasalRate(unitsPerHour: Double) throws -> Double

    func pumpManagerStatus() throws -> PumpManagerStatus

    func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) throws -> DoseProgressReporter?

    func syncBasalRateSchedule(items basals: [BasalProfileEntry], concentration: Double) async throws -> [BasalProfileEntry]?

    func syncDeliveryLimits(pumpSettings: PumpSettings) async throws -> (maximumBolus: Double?, maximumBasalRate: Double?)?
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

extension WeakSynchronizedSet: @retroactive @unchecked Sendable {}

private let lastEventDateKey = "BaseDeviceDataManager.lastEventDate"

private enum ConfigOverrides {
    static let allowUploadsFromNightscoutCGM = {
        // can be overriden in ConfigOverride.xcconfig
        // while testing, it is important to be able to have nightscout as the cgm, AND to be able to upload glucose to another nightscout
        // nightscout cgm UI does not have a toggle for this and always disables uploads (as it should)
        (Bundle.main.object(forInfoDictionaryKey: "ALLOW_UPLOADS_FROM_NIGHTSCOUT_CGM") as? String)?.lowercased() == "yes"
    }()
}

final class BaseDeviceDataManager: DeviceDataManager, AppServiceSync {
    private let processQueue = DispatchQueue.markedQueue(label: "BaseDeviceDataManager.processQueue")

    private let pumpHistoryStorage: PumpHistoryStorage
    private let alertHistoryStorage: AlertHistoryStorage
    private let storage: FileStorage
    private let glucoseStorage: GlucoseStorage
    private let settingsManager: SettingsManager
    private let bloodGlucoseManager: BloodGlucoseManager
    private let bluetoothProvider: BluetoothStateManager
    private let calibrationService: CalibrationService
    private let router: Router
    private let appCoordinator: AppCoordinator

    private let lifetime = Lifetime()

    private let pluginManager = PluginManager()

    private let displayGlucoseUnitObservers = WeakSynchronizedSet<DisplayGlucoseUnitObserver>()

    @MainActor private let displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)

    private let lastEventDate = Locked<Date?>(UserDefaults.standard.object(forKey: lastEventDateKey) as? Date)

    private let latestCgmReadingDate: Locked<Date?> = Locked(nil)

    // not using @PersistedProperty as an annotation directly because using a var breaks Sendable for DeviceDataManager
    private let rawCGMManagerStore = PersistedProperty<CGMManager.RawValue>(key: "CGMManagerState")
    private var rawCGMManager: CGMManager.RawValue? {
        get { rawCGMManagerStore.wrappedValue }
        set { rawCGMManagerStore.wrappedValue = newValue }
    }

    private let cgmManagerLocked: ManagerBox<CGMManager?> = ManagerBox(nil)

    private var cgmManager: CGMManager? {
        cgmManagerLocked.value
    }

    // not using @PersistedProperty as an annotation directly because using a var breaks Sendable for DeviceDataManager
    private let rawPumpManagerStore = PersistedProperty<PumpManager.RawValue>(key: "PumpManagerState")
    private var rawPumpManager: PumpManager.RawValue? {
        get { rawPumpManagerStore.wrappedValue }
        set {
            rawPumpManagerStore.wrappedValue = newValue
            if newValue == nil {
                lastKnownReservoir = nil
            }
        }
    }

    private let pumpManagerLocked: ManagerBox<PumpManagerUI?> = ManagerBox(nil)

    // not using @PersistedProperty as an annotation directly because using a var breaks Sendable for DeviceDataManager
    /// persist the latest known reservoir value
    private let lastKnownReservoirStore = PersistedProperty<ReservoirReading.RawValue>(key: "lastKnownReservoir")
    private var lastKnownReservoir: ReservoirReading? {
        get { .init(from: lastKnownReservoirStore.wrappedValue) }
        set { lastKnownReservoirStore.wrappedValue = newValue?.rawValue }
    }

    private var pumpManager: PumpManagerUI? {
        pumpManagerLocked.value
    }

    init(
        pumpHistoryStorage: PumpHistoryStorage,
        alertHistoryStorage: AlertHistoryStorage,
        storage: FileStorage,
        glucoseStorage: GlucoseStorage,
        settingsManager: SettingsManager,
        bloodGlucoseManager: BloodGlucoseManager,
        bluetoothProvider: BluetoothStateManager,
        calibrationService: CalibrationService,
        router: Router,
        appCoordinator: AppCoordinator
    ) {
        self.pumpHistoryStorage = pumpHistoryStorage
        self.alertHistoryStorage = alertHistoryStorage
        self.storage = storage
        self.glucoseStorage = glucoseStorage
        self.settingsManager = settingsManager
        self.bloodGlucoseManager = bloodGlucoseManager
        self.bluetoothProvider = bluetoothProvider
        self.calibrationService = calibrationService
        self.router = router
        self.appCoordinator = appCoordinator

        // TODO: does this belong here?
        UIDevice.current.isBatteryMonitoringEnabled = true
        // initial managers restoration happens in start() which is called at the start of the app
    }

    private func setCgmManager(_ cgmManager: CGMManager?) {
        dispatchPrecondition(condition: .onQueue(processQueue))

        let oldValue = self.cgmManager
        cgmManagerLocked.mutate { $0 = cgmManager }

        oldValue?.cgmManagerDelegate = nil
        oldValue?.delegateQueue = nil

        setupCGM()

        rawCGMManager = cgmManager?.rawValue
        UserDefaults.standard.clearLegacyCGMManagerRawValue()
    }

    private func setPumpManager(_ pumpManager: PumpManagerUI?) {
        dispatchPrecondition(condition: .onQueue(processQueue))

        let oldValue = self.pumpManager
        pumpManagerLocked.mutate { $0 = pumpManager }

        oldValue?.pumpManagerDelegate = nil
        oldValue?.delegateQueue = nil

        // If the current CGMManager is a PumpManager, we clear it out.
        if cgmManager is PumpManagerUI {
            setCgmManager(nil)
        }

        setupPump()

        rawPumpManager = pumpManager?.rawValue
        UserDefaults.standard.clearLegacyPumpManagerRawValue()
    }

    // this is called on app start
    func start() {
        processQueue.sync {
            if let pumpManagerRawValue = rawPumpManager ?? UserDefaults.standard.legacyPumpManagerRawValue {
                pumpManagerLocked.mutate { $0 = pumpManagerFromRawValue(pumpManagerRawValue) }
            }

            if let cgmManagerRawValue = rawCGMManager ?? UserDefaults.standard.legacyCgmManagerRawValue {
                cgmManagerLocked.mutate { $0 = cgmManagerFromRawValue(cgmManagerRawValue) }

                // Handle case of PumpManager providing CGM
                if cgmManager == nil, pumpManagerTypeFromRawValue(cgmManagerRawValue) != nil {
                    cgmManagerLocked.mutate { $0 = pumpManager as? CGMManager }
                }
            }

            setupPump()
            setupCGM()
        }

        appCoordinator.alertsUpdates
            .receive(on: processQueue)
            .sink { [weak self] alerts in
                guard let self else { return }
                alerts.forEach { alert in
                    if alert.acknowledgedDate == nil {
                        self.ackAlert(alert: alert)
                    }
                }
            }
            .store(in: lifetime)

        appCoordinator.heartbeat
            .receive(on: processQueue)
            .sink { [weak self] _ in
                self?.heartbeat(forceRecommendLoop: true)
            }
            .store(in: lifetime)

        appCoordinator.appBecomeActiveEvents
            .receive(on: processQueue)
            .sink { [weak self] _ in
                self?.updatePumpManagerBLEHeartbeatPreference()
            }
            .store(in: lifetime)

        appCoordinator.settings.map(\.units).removeDuplicates()
            .receive(on: DispatchQueue.main) // important to be on main because of MainActor.assumeIsolated below
            .sink { units in
                let loopkitUnit: HKUnit = units == .mmolL ? .millimolesPerLiter : .milligramsPerDeciliter
                MainActor.assumeIsolated {
                    self.displayGlucosePreference.unitDidChange(to: loopkitUnit)
                    self.notifyObserversOfDisplayGlucoseUnitChange(to: loopkitUnit)
                }
            }
            .store(in: lifetime)
    }

    var availablePumpManagers: [PumpManagerDescriptor] {
        let pumpManagers = pluginManager.availablePumpManagers + availableStaticPumpManagers
        return pumpManagers.sorted(by: { $0.localizedTitle < $1.localizedTitle })
    }

    @MainActor func setupPumpManager(
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

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        if let pumpManager = pumpManagerTypeByIdentifier(managerIdentifier) {
            return pumpManager
        }

        // see: https://github.com/LoopKit/Loop/pull/2426/changes

        /// The pumpManager was not found for managerIdentifier. If this was for an "Omnipod" (OmniKit) or
        /// "Omnipod-DASH" (OmniBLE), have the universal "Omni" pumpManager (OmnipodKit) handle instead.
        let OmniStr = "Omni"
        if managerIdentifier.hasPrefix(OmniStr) {
            return pumpManagerTypeByIdentifier(OmniStr)
        }

        return nil
    }

    func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    private func updatePumpData(completion: @escaping @Sendable() -> Void) {
        guard let pumpManager = pumpManager else {
            debug(.deviceManager, "Pump is not set, skip updating")
            completion()
            return
        }
        guard pumpManager.isOnboarded else {
            debug(.deviceManager, "Pump is not onboarded, skip updating")
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
            var allowCalibrations: Bool
            if let cgmManager = cgmManager {
                sessionStart = KnownPlugins.sessionStart(cgmManager: cgmManager)
                allowCalibrations = KnownPlugins.allowCalibrations(for: cgmManager) && !calibrationService.calibrations.isEmpty
            } else {
                allowCalibrations = false
            }

            latestCgmReadingDate.mutate { $0 = values.map(\.date).max() }

            let bloodGlucose = values.map { newGlucoseSample -> BloodGlucose in
                let quantity = newGlucoseSample.quantity
                let mgdl = quantity.doubleValue(for: .milligramsPerDeciliter)
                let uncalibrated = Int(mgdl)

                let value = allowCalibrations ?
                    Int(calibrationService.calibrate(value: mgdl)) :
                    Int(mgdl)

                let dateRoundedTo1Second = newGlucoseSample.date.roundedTo1Second
                return BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: value,
                    direction: .init(trendType: newGlucoseSample.trend),
                    date: Decimal(Int(dateRoundedTo1Second.timeIntervalSince1970 * 1000)),
                    dateString: dateRoundedTo1Second,
                    unfiltered: Decimal(value),
                    uncalibrated: Decimal(uncalibrated),
                    filtered: nil,
                    noise: nil,
                    glucose: value,
                    type: "sgv",
                    sessionStartDate: sessionStart,
                )
            }

            completion(bloodGlucose)
        case .unreliableData:
            warning(.deviceManager, "CGM Manager - unreliable data")
            completion([])
        case .noData:
            completion([])
        case let .error(error):
            warning(
                .deviceManager,
                "CGM Manager - reading error: \(String(describing: error))"
            )
//            errorSubject.send(error)
            appCoordinator.sendDeviceError(error)
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
        return availableCGMManagers.sorted(by: { $0.localizedTitle < $1.localizedTitle })
    }

    @MainActor func setupCGMManager(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool = false) -> Swift
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

    @MainActor func cgmManagerSettingsView() -> CGMManagerViewController? {
        guard let cgmManager = self.cgmManager as? CGMManagerUI else { return nil }
        var vc = cgmManager.settingsViewController(
            bluetoothProvider: bluetoothProvider,
            displayGlucosePreference: displayGlucosePreference,
            colorPalette: .default,
            allowDebugFeatures: true
        )
        vc.cgmManagerOnboardingDelegate = self
        return vc
    }

    @MainActor func pumpManagerSettingsView() -> PumpManagerViewController? {
        guard let pumpManager else { return nil }
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
            setCgmManager(nil)
        }
    }

    struct UnknownCGMManagerIdentifierError: Error {}

    @MainActor fileprivate func setupCGMManagerUI(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool) -> Swift
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
        setCgmManager(cgmManager)
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
        // storeNewBloodGlucose runs in a Task with callback so that we don't block the CGM manager
        bloodGlucoseManager.storeNewBloodGlucose(bloodGlucose: bloodGlucose) { newGlucoseStored in
            if newGlucoseStored || forceRecommendLoop {
                guard !self.appCoordinator.isLooping.value else {
                    debug(
                        .deviceManager,
                        "new glucose saved, but the loop is already in progress - skipping pump sync and loop recommendation"
                    )
                    return
                }
                self.processQueue.safeSync {
                    self.updatePumpData {
//                        self._recommendsLoop.send(())
                        self.appCoordinator.sendRecommendsLoop()
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

    private func addDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        displayGlucoseUnitObservers.insert(observer, queue: DispatchQueue.main)
        // observer is a non-Sendable CGM manager, but LoopKit synchronizes its state internally,
        // so handing it to the main actor for this one call is safe.
        nonisolated(unsafe) let observer = observer
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                observer.unitDidChange(to: self.displayGlucosePreference.unit)
            }
        }
    }

    private func removeDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        displayGlucoseUnitObservers.removeElement(observer)
    }

    private func notifyObserversOfDisplayGlucoseUnitChange(to displayGlucoseUnit: HKUnit) {
        displayGlucoseUnitObservers.forEach {
            $0.unitDidChange(to: displayGlucoseUnit)
        }
    }
}

// MARK: - PumpManagerDelegate

extension BaseDeviceDataManager: PumpManagerDelegate {
    func pumpManagerPumpWasReplaced(_: PumpManager) {
        debug(.deviceManager, "pumpManagerPumpWasReplaced")
    }

    var detectedSystemTimeOffset: TimeInterval {
        // TODO: [loopkit] loop has this:
        // trustedTimeChecker.detectedSystemTimeOffset
        // but is it even used by any real device manager?
        0
    }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "PumpManager \(pumpManager.pluginIdentifier) didAdjustPumpClockBy \(adjustment)")
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        // TODO: what is this scenario?
        if self.pumpManager == nil, let newPumpManager = pumpManager as? PumpManagerUI {
            setPumpManager(newPumpManager)
        } else {
            rawPumpManager = pumpManager.rawValue
        }

        // try reading reservoir, if nil is returned - keep the previous value (hopefully received in pumpManager(didReadReservoirValue))
        if let reservoir = KnownPlugins.pumpReservoir(pumpManager) {
            lastKnownReservoir = reservoir
        }

        dispatchPumpInfo()
        dispatchPumpStatus()
    }

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "PumpManager:\(String(describing: type(of: pumpManager))) did fire heartbeat")
        heartbeat(forceRecommendLoop: false)
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return pumpManagerMustProvideBLEHeartbeat
    }

    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")

        dispatchPumpStatus()

        if status.insulinType != oldStatus.insulinType {
            let newInsulinCurve = status.insulinType
            Task { [settingsManager] in
                await settingsManager.updateInsulinCurve(newInsulinCurve)
            }
        }

        if status.deliveryIsUncertain != oldStatus.deliveryIsUncertain {
            debug(.deviceManager, "delivery is uncertain: \(status)")
        }
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' will deactivate")

        setPumpManager(nil)
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        debug(
            .deviceManager,
            "PumpManager:\(String(describing: type(of: pumpManager))) did update pumpRecordsBasalProfileStartEvents to \(String(describing: pumpRecordsBasalProfileStartEvents))"
        )
    }

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "error: \(error.localizedDescription), reason: \(String(describing: error.failureReason))")
        appCoordinator.sendDeviceError(error)
    }

    private struct PumpEventCompletion: @unchecked Sendable {
        private let completion: ((any Error)?) -> Void
        private let processQueue: DispatchQueue
        init(_ completion: @escaping ((any Error)?) -> Void, processQueue: DispatchQueue) {
            self.completion = completion
            self.processQueue = processQueue
        }

        func callAsFunction(_ error: (any Error)?) {
            processQueue.async { completion(error) }
        }
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

        let date = lastEventDate.mutate {
            $0 = events.last?.date
        }
        if let date {
            UserDefaults.standard.set(date, forKey: lastEventDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastEventDateKey)
        }

        let safeCompletion = PumpEventCompletion(completion, processQueue: processQueue)
        Task { [pumpHistoryStorage] in
            do {
                try await pumpHistoryStorage.storePumpEvents(events)
                safeCompletion(nil)
            } catch {
                safeCompletion(error)
            }
        }
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

        lastKnownReservoir = .units(Decimal(units))

        dispatchPumpStatus()

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
        lastEventDate.value?.addingTimeInterval(-15.minutes.timeInterval) ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }

    var automaticDosingEnabled: Bool {
        // none of the actual pump plugins seem to even read this var
        true
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: AlertIssuer {
    func issueAlert(_ alert: Alert) {
        let entry = AlertEntry(from: alert)
        Task { [alertHistoryStorage] in
            await alertHistoryStorage.storeAlert(entry)
        }
    }

    func retractAlert(identifier: Alert.Identifier) {
        let managerIdentifier = identifier.managerIdentifier
        let alertIdentifier = identifier.alertIdentifier
        Task { [alertHistoryStorage] in
            await alertHistoryStorage.deleteAlert(
                managerIdentifier: managerIdentifier,
                alertIdentifier: alertIdentifier
            )
        }
    }
}

extension BaseDeviceDataManager: DeviceManagerDelegate {
    func deviceManager(
        _: LoopKit.DeviceManager,
        logEventForDeviceIdentifier deviceIdentifier: String?,
        type _: LoopKit.DeviceLogEntryType,
        message: String,
        completion: ((Error?) -> Void)?
    ) {
        debug(.deviceManager, "device Manager for \(String(describing: deviceIdentifier)) : \(message)")
        completion?(nil)
    }
}

// MARK: - CGMManagerDelegate

extension BaseDeviceDataManager: CGMManagerDelegate {
    func startDateToFilterNewData(for _: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(processQueue))

        return latestCgmReadingDate.value
//            .map { $0.addingTimeInterval(-10.minutes.timeInterval) } // additional time to calculate directions
    }

    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "CGM Manager with identifier \(manager.pluginIdentifier) wants deletion")

        if let cgmManagerUI = cgmManager as? CGMManagerUI {
            removeDisplayGlucoseUnitObserver(cgmManagerUI)
        }
        setCgmManager(nil)
        displayGlucoseUnitObservers.cleanupDeallocatedElements()
    }

    func cgmManager(_: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "hasNew readingResult: \(readingResult)")
        processCGMReadingResultAndLoop(readingResult: readingResult, forceRecommendLoop: false)
    }

    func cgmManager(_: LoopKit.CGMManager, hasNew events: [PersistedCgmEvent]) {
        for event in events {
            if event.type == .sensorStart {
                // libre manager emits sensorStart when it detects a new sensor
                // the calibration service subscribes to this event to clear calibrations
                appCoordinator.sendNewSensorDetected()
            }
        }
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        rawCGMManager = manager.rawValue
        dispatchCgmStatus()
    }

    func credentialStoragePrefix(for _: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        UUID().uuidString
    }

    func cgmManager(_: CGMManager, didUpdate _: CGMManagerStatus) {}
}

// MARK: - AlertPresenter

extension BaseDeviceDataManager {
//    func alertDidUpdate(_ alerts: [AlertEntry]) {
//        alerts.forEach { alert in
//            if alert.acknowledgedDate == nil {
//                ackAlert(alert: alert)
//            }
//        }
//    }

    private func ackAlert(alert: AlertEntry) {
        let typeMessage: MessageType
        let alertUp = alert.alertIdentifier.uppercased()
        if alertUp.contains("FAULT") || alertUp.contains("ERROR") {
            typeMessage = .errorPump
        } else {
            typeMessage = .warning
        }

        let messageCont = MessageContent(content: alert.contentBody ?? "Unknown", type: typeMessage)

        processQueue.async {
            // we cannot rely on completion callback to be always called, so...
            // present the alert and acknowledge in the storage upfront
            // and store the error in case the manager completes with error
            // TODO: this has been fixed in the offending device manager, clean this up
//            self.alertHistoryStorage.ackAlert(
//                managerIdentifier: alert.managerIdentifier,
//                alertIdentifier: alert.alertIdentifier,
//                error: nil
//            )
            self.appCoordinator.sendAlertMessage(messageCont)

            var alertResponder: AlertResponder?
            if let pumpManager = self.pumpManager, alert.managerIdentifier == pumpManager.pluginIdentifier {
                alertResponder = pumpManager
            } else if let cgmManager = self.cgmManager, alert.managerIdentifier == cgmManager.pluginIdentifier {
                alertResponder = cgmManager
            }
            alertResponder?.acknowledgeAlert(alertIdentifier: alert.alertIdentifier) { error in
                if let error = error {
                    debug(.deviceManager, "acknowledge failed with error \(error.localizedDescription)")
                }

                self.alertHistoryStorage.ackAlert(
                    managerIdentifier: alert.managerIdentifier,
                    alertIdentifier: alert.alertIdentifier,
                    error: error?.localizedDescription
                )
            }

//            self.broadcaster.notify(PumpNotificationObserver.self, on: self.processQueue) {
//                $0.pumpNotification(alert: alert)
//            }
            self.appCoordinator.sendPumpNotification(alert)
        }
    }
}

extension BaseDeviceDataManager {
    func updatePumpManagerBLEHeartbeatPreference() {
        pumpManager?.setMustProvideBLEHeartbeat(pumpManagerMustProvideBLEHeartbeat)
    }

    func cgmInfo() -> GlucoseSourceInfo? {
        guard let cgmManager = self.cgmManager else { return nil }
        return KnownPlugins.cgmInfo(for: cgmManager)
    }
}

// MARK: - CGMManagerOnboardingDelegate

extension BaseDeviceDataManager: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager cgmManager: CGMManagerUI) {
        processQueue.async {
            debug(.deviceManager, "CGM manager with identifier '\(cgmManager.pluginIdentifier)' created")
            self.setCgmManager(cgmManager)
        }
    }

    func cgmManagerOnboarding(didOnboardCGMManager cgmManager: CGMManagerUI) {
        precondition(cgmManager.isOnboarded)
        debug(.deviceManager, "CGM manager with identifier '\(cgmManager.pluginIdentifier)' onboarded")

        refreshDeviceData()
    }
}

// MARK: - PumpManagerOnboardingDelegate

extension BaseDeviceDataManager: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        processQueue.async {
            debug(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' created")
            self.setPumpManager(pumpManager)
            if let insulinType = pumpManager.status.insulinType {
                Task {
                    await self.settingsManager.updateInsulinCurve(insulinType)
                }
            }
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        precondition(pumpManager.isOnboarded)
        debug(.deviceManager, "Pump manager with identifier '\(pumpManager.pluginIdentifier)' onboarded")

        refreshDeviceData()
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {}
}

// MARK: - PersistedAlertStore

extension BaseDeviceDataManager: PersistedAlertStore {
    // none of the device managers ever calls any of these functions ¯\_(ツ)_/¯

    func doesIssuedAlertExist(identifier _: Alert.Identifier, completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(false))
    }

    func lookupAllUnretracted(managerIdentifier _: String, completion: @escaping (Result<[PersistedAlert], Error>) -> Void) {
        completion(.success([]))
    }

    func lookupAllUnacknowledgedUnretracted(
        managerIdentifier _: String,
        completion: @escaping (Result<[PersistedAlert], Error>) -> Void
    ) {
        completion(.success([]))
    }

    func recordRetractedAlert(_: Alert, at _: Date) {}
}

private extension BaseDeviceDataManager {
    private func dispatchPumpInfo() {
        guard let pumpManager else {
            appCoordinator.setPumpInfo(nil)
            return
        }

        let info = PumpDisplayInfo(
            identifier: pumpManager.pluginIdentifier,
            name: pumpManager.localizedTitle,
            isOnboarded: pumpManager.isOnboarded,
            image: pumpManager.smallImage,
            expiresAt: KnownPlugins.pumpExpirationDate(pumpManager),
            podActivatedAt: KnownPlugins.pumpActivationDate(pumpManager),
        )

        appCoordinator.setPumpInfo(info)
    }

    private func dispatchPumpStatus() {
        guard let pumpManager = self.pumpManager else {
            appCoordinator.setPumpStatus(nil)
            appCoordinator.setBolusInProgress(false)
            appCoordinator.setManualTempBasal(false)
            return
        }

        let status = pumpStatus(for: pumpManager)
        appCoordinator.setPumpStatus(status)
        if case .inProgress = pumpManager.status.bolusState {
            self.appCoordinator.setBolusInProgress(true)
        } else {
            appCoordinator.setBolusInProgress(false)
        }
        appCoordinator.setManualTempBasal(KnownPlugins.isManualTempBasalActive(pumpManager) ?? false)
    }

    private func dispatchCgmInfo() {
        guard let cgmManager = self.cgmManager else {
            appCoordinator.setCgmInfo(nil)
            appCoordinator.setCgmStatus(nil)
            return
        }

        let pumpIsCgm: Bool
        if let pump = pumpManager {
            pumpIsCgm = (cgmManager as AnyObject) === (pump as AnyObject)
        } else {
            pumpIsCgm = false
        }

        let info = CgmDisplayInfo(
            identifier: cgmManager.pluginIdentifier,
            identifierForStatistics: KnownPlugins.cgmIdForStatistics(for: cgmManager),
            name: cgmManager.localizedTitle,
            isOnboarded: cgmManager.isOnboarded,
            image: (cgmManager as? CGMManagerUI)?.smallImage,
            pumpIsCgm: pumpIsCgm,
            providesHeartbeat: cgmManager.providesBLEHeartbeat,
            sensorDays: KnownPlugins.cgmExpirationByPluginIdentifier(cgmManager),
            allowCalibrations: KnownPlugins.allowCalibrations(for: cgmManager),
            appURL: cgmManager.appURL,
            glucoseUploadSupported: KnownPlugins.glucoseUploadingAvailable(for: cgmManager)
        )

        appCoordinator.setCgmInfo(info)
    }

    private func dispatchCgmStatus() {
        guard let cgmManager else {
            appCoordinator.setCgmStatus(nil)
            return
        }

        let status = CgmDisplayStatus(
            statusHighlight: (cgmManager as? CGMManagerUI)?.cgmStatusHighlight?.localizedMessage,
            sessionStartDate: KnownPlugins.sessionStart(cgmManager: cgmManager),
            shouldUploadGlucose: cgmManager.shouldSyncToRemoteService || ConfigOverrides.allowUploadsFromNightscoutCGM
        )

        appCoordinator.setCgmStatus(status)
    }

    private func setupCGM() {
        dispatchPrecondition(condition: .onQueue(processQueue))

        updatePumpManagerBLEHeartbeatPreference()

        if let cgmManager {
            cgmManager.cgmManagerDelegate = self
            cgmManager.delegateQueue = processQueue

            if let cgmManagerUI = cgmManager as? CGMManagerUI {
                addDisplayGlucoseUnitObserver(cgmManagerUI)
            }
        }

        dispatchCgmInfo()
        dispatchCgmStatus()
    }

    private func setupPump() {
        dispatchPrecondition(condition: .onQueue(processQueue))

        updatePumpManagerBLEHeartbeatPreference()

        if let pumpManager {
            pumpManager.pumpManagerDelegate = self
            pumpManager.delegateQueue = processQueue
        }
        dispatchPumpInfo()
        dispatchPumpStatus()
    }
}

extension BaseDeviceDataManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) async throws {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pump.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error = error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    debug(.apsManager, "Temp basal succeeded: \(unitsPerHour) for: \(duration)")
                    continuation.resume()
                }
            }
        }
    }

    func enactBolus(units: Double, automatic: Bool) async throws {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return try await withCheckedThrowingContinuation { continuation in
            // convert automatic
            let automaticValue = automatic ? BolusActivationType.automatic : BolusActivationType.manualRecommendationAccepted

            pump.enactBolus(units: units, activationType: automaticValue) { error in
                if let error = error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    debug(.apsManager, "Bolus succeeded: \(units)")
                    continuation.resume()
                }
            }
        }
    }

    func cancelBolus() async throws -> DoseEntry? {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pump.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeeded")
                    continuation.resume(returning: dose)
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    continuation.resume(throwing: APSError.pumpError(error))
                }
            }
        }
    }

    func suspendDelivery() async throws {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pump.suspendDelivery { error in
                if let error = error {
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func resumeDelivery() async throws {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return try await withCheckedThrowingContinuation { continuation in
            pump.resumeDelivery { error in
                if let error = error {
                    continuation.resume(throwing: APSError.pumpError(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

//    func pumpStatus() throws -> PumpStatus {
//        guard let pump = pumpManager else {
//            throw APSError.invalidPumpState(message: "Pump not configured")
//        }
//        return pump.status.pumpStatus
//    }

    func roundBolus(amount: Decimal, maxBolus: Decimal) -> Decimal {
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(maxBolus)))
        return min(rounded, maxBolus)
    }

    func roundToSupportedBolusVolume(units: Double) throws -> Double {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }

        return pump.roundToSupportedBolusVolume(units: units)
    }

    func roundToSupportedBasalRate(unitsPerHour: Double) throws -> Double {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return pump.roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
    }

    func pumpManagerStatus() throws -> PumpManagerStatus {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return pump.status
    }

    func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) throws -> DoseProgressReporter? {
        guard let pump = pumpManager else {
            throw APSError.invalidPumpState(message: "Pump not configured")
        }
        return pump.createBolusProgressReporter(reportingOn: dispatchQueue)
    }

    func syncBasalRateSchedule(items basals: [BasalProfileEntry], concentration: Double) async throws -> [BasalProfileEntry]? {
        guard let pump = pumpManager else { return nil }

        let scheduleItems = basals.map { $0.toLoopKit(concentration: concentration) }

        return try await withCheckedThrowingContinuation { continuation in
            pump.syncBasalRateSchedule(items: scheduleItems) { result in
                switch result {
                case let .success(saved):
                    debug(.service, "Basals saved to pump!")
                    let adjustedBasals = saved.items
                        .map { BasalProfileEntry(startTime: $0.startTime, rate: $0.value * concentration) }
                    continuation.resume(returning: adjustedBasals)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func syncDeliveryLimits(pumpSettings: PumpSettings) async throws -> (maximumBolus: Double?, maximumBasalRate: Double?)? {
        guard let pump = pumpManager else { return nil }
        let limits = DeliveryLimits(
            maximumBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: Double(pumpSettings.maxBasal)),
            maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: Double(pumpSettings.maxBolus))
        )
        return try await withCheckedThrowingContinuation { continuation in
            pump.syncDeliveryLimits(limits: limits) { result in
                switch result {
                case let .success(actual):
                    // Store the limits from the pumpManager to ensure the correct values
                    // Example: Dana pumps don't allow to set these limits, only to fetch them
                    // This will ensure we always have the correct values stored
                    let settings = (
                        maximumBolus: actual.maximumBolus?.doubleValue(for: .internationalUnit()),
                        maximumBasalRate: actual.maximumBasalRate?.doubleValue(for: .internationalUnitsPerHour)
                    )

                    continuation.resume(returning: settings)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func pumpStatus(for pumpManager: PumpManagerUI) -> PumpDisplayStatus? {
        let pumpManagerStatus = pumpManager.status
        let batteryPercent = Int((pumpManagerStatus.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: batteryPercent,
            voltage: nil,
            string: batteryPercent >= 10 ? .normal : .low,
            display: pumpManager.status.pumpBatteryChargeRemaining != nil
        )

        let isBolusing = pumpManagerStatus.bolusState != .noBolus
        let isSuspended = pumpManagerStatus.basalDeliveryState?.isSuspended ?? true
        let statusType: PumpDisplayStatus.StatusType = isSuspended ? .suspended : (isBolusing ? .bolusing : .normal)

        return PumpDisplayStatus(
            status: statusType,
            reservoir: lastKnownReservoir,
            statusHighlight: pumpManager.pumpStatusHighlight?.localizedMessage,
            timeZone: pumpManagerStatus.timeZone,
            battery: battery,
            deliveryIsUncertain: pumpManagerStatus.deliveryIsUncertain,
            isSuspended: isSuspended,
            isBolusing: isBolusing,
            supportedBasalRates: pumpManager.supportedBasalRates,
            supportedBolusVolumes: pumpManager.supportedBolusVolumes,
            timestamp: Date.now
        )
    }

    func currentPumpStatus() -> PumpDisplayStatus? {
        guard let pumpManager else { return nil }
        return pumpStatus(for: pumpManager)
    }
}

// A Sendable wrapper around LoopKit's Locked.
// BaseDeviceDataManager uses this class to hold and safely modify references to CGM/pump managers.
// * Locked is not declared Sendable
// * CGM/pump managers are not Sendable - so our `@retroactive @unchecked Sendable` from LoopKit+Extensions.swift does not apply
private final class ManagerBox<T>: @unchecked Sendable {
    private let locked: Locked<T>
    init(_ value: T) { locked = Locked(value) }
    var value: T { get { locked.value } set { locked.value = newValue } }
    @discardableResult func mutate(_ body: (inout T) -> Void) -> T { locked.mutate(body) }
}
