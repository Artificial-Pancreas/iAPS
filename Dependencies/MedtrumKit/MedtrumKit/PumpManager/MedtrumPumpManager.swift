import CoreBluetooth
import HealthKit
import LoopKit

public class MedtrumPumpManager: DeviceManager {
    public static let pluginIdentifier = "Medtrum"
    public var localizedTitle: String {
        LocalizedString("Medtrum", comment: "Generic title of the Medtrum pump manager") + " " + state.pumpName
    }

    public let managerIdentifier: String = "MedtrumKit"

    private let log = MedtrumLogger(category: "MedtrumPumpManager")

    public let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()

    public var state: MedtrumPumpState
    var oldState: MedtrumPumpState
    public var rawState: PumpManager.RawStateValue {
        state.rawValue
    }

    private var doseReporter: MedtrumDoseProgressReporter?
    private var doseEntry: UnfinalizedDose?

    let bluetooth: BluetoothManager

    init(state: MedtrumPumpState) {
        self.state = state
        oldState = MedtrumPumpState(rawValue: state.rawValue)
        bluetooth = BluetoothManager()

        bluetooth.pumpManager = self
    }

    public required convenience init?(rawState: RawStateValue) {
        self.init(state: MedtrumPumpState(rawValue: rawState))
    }

    public var isOnboarded: Bool {
        state.isOnboarded
    }

    public static var onboardingMaximumBasalScheduleEntryCount: Int {
        48
    }

    public static var onboardingSupportedBasalRates: [Double] {
        // During onboard, we assume 300u -> 0.00-30U/hr
        // 0 U/hr is a supported scheduled basal rate
        (0 ... 600).map { Double($0) / 20 }
    }

    public static var onboardingSupportedBolusVolumes: [Double] {
        // 0.05 units for rates between 0.05-30U
        // 0 is not a supported bolus volume
        (1 ... 600).map { Double($0) / 20 }
    }

    public static var onboardingSupportedMaximumBolusVolumes: [Double] {
        MedtrumPumpManager.onboardingSupportedBolusVolumes
    }

    public var delegateQueue: DispatchQueue! {
        get {
            pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }

    public var supportedBasalRates: [Double] {
        guard !state.pumpSN.isEmpty else {
            return MedtrumPumpManager.onboardingSupportedBasalRates
        }

        // 300U -> 0.05-30U
        // 200U -> 0.05-25U
        return state.pumpName.contains("300U") ? MedtrumPumpManager.onboardingSupportedBasalRates : (0 ... 500)
            .map { Double($0) / 20 }
    }

    public var supportedBolusVolumes: [Double] {
        MedtrumPumpManager.onboardingSupportedBolusVolumes
    }

    public var supportedMaximumBolusVolumes: [Double] {
        MedtrumPumpManager.onboardingSupportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        MedtrumPumpManager.onboardingMaximumBasalScheduleEntryCount
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        TimeInterval(minutes: 30)
    }

    public var debugDescription: String {
        state.debugDescription
    }

    public func acknowledgeAlert(alertIdentifier _: LoopKit.Alert.AlertIdentifier, completion: @escaping ((any Error)?) -> Void) {
        completion(nil)
    }

    public func getSoundBaseURL() -> URL? {
        nil
    }

    public func getSounds() -> [LoopKit.Alert.Sound] {
        []
    }

    public var pumpManagerDelegate: LoopKit.PumpManagerDelegate? {
        get {
            pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
        }
    }

    private func device(_ state: MedtrumPumpState) -> HKDevice {
        HKDevice(
            name: state.pumpName,
            manufacturer: "Medtrum",
            model: state.model,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: state.swVersion,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }
}

public extension MedtrumPumpManager {
    var pumpRecordsBasalProfileStartEvents: Bool {
        false
    }

    var pumpReservoirCapacity: Double {
        state.reservoir
    }

    var lastSync: Date? {
        state.lastSync
    }

    var status: PumpManagerStatus {
        self.status(state)
    }

    private func status(_ state: MedtrumPumpState) -> PumpManagerStatus {
        let bolusState: LoopKit.PumpManagerStatus.BolusState
        switch state.bolusState {
        case .noBolus:
            bolusState = .noBolus
        case .canceling:
            bolusState = .canceling
        case .inProgress:
            if let dose = doseEntry?.toDoseEntry() {
                bolusState = .inProgress(dose)
            } else {
                bolusState = .noBolus
            }
        }

        return PumpManagerStatus(
            timeZone: TimeZone.current,
            device: device(state),
            pumpBatteryChargeRemaining: nil, // Patch pumps do not need to report back battery status
            basalDeliveryState: state.basalDeliveryState,
            bolusState: bolusState,
            insulinType: state.insulinType
        )
    }

    private func bolusState(_ bolusState: BolusState) -> PumpManagerStatus.BolusState {
        switch bolusState {
        case .noBolus:
            return .noBolus
        case .canceling:
            return .canceling
        case .inProgress:
            if let dose = doseEntry?.toDoseEntry() {
                return .inProgress(dose)
            }

            return .noBolus
        }
    }

    func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        guard Date.now.timeIntervalSince(state.lastSync) > .minutes(4) else {
            log.warning("Skipping status update -> data is fresh: \(Date.now.timeIntervalSince(state.lastSync)) sec")
            completion?(state.lastSync)
            return
        }

        guard state.pumpState.rawValue >= PatchState.active.rawValue else {
            log.error("(ensureCurrentPumpData) patch not in active state yet")
            completion?(nil)
            return
        }

        syncPumpData(completion: completion)
    }

    func syncPumpData(completion: ((Date?) -> Void)?) {
        #if targetEnvironment(simulator)
            pumpDelegate.notify { delegate in
                delegate?.pumpManager(self, didReadReservoirValue: self.state.reservoir, at: Date.now) { _ in }

                self.state.lastSync = Date.now
                self.notifyStateDidChange()
            }
            return
        #endif

        log.info("Sync pump data")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                completion?(nil)
                return
            }

            let syncPacket = SynchronizePacket()
            let syncResult = await self.bluetooth.write(syncPacket)

            switch syncResult {
            case let .failure(error):
                self.log.error("Failed to write: \(error.localizedDescription)")
                completion?(nil)
                return

            case let .success(data):
                guard let syncResponse = data as? SynchronizePacketResponse else {
                    self.log.error("Invalid response data...")
                    completion?(nil)
                    return
                }

                do {
                    self.log.info("Manual sync: \(String(data: try JSONEncoder().encode(syncResponse), encoding: .utf8) ?? "")")
                } catch {
                    self.log.warning("State update: Failed to encode JSON")
                }

                self.pumpDelegate.notify { delegate in
                    syncState(
                        syncResponse: syncResponse,
                        state: self.state,
                        delegate: delegate,
                        pumpManager: self
                    )
                    self.notifyStateDidChange()
                }

                completion?(Date.now)
            }
        }
    }

    func setMustProvideBLEHeartbeat(_: Bool) {}

    func createBolusProgressReporter(reportingOn _: DispatchQueue) -> (any LoopKit.DoseProgressReporter)? {
        doseReporter
    }

    func estimatedDuration(toBolus units: Double) -> TimeInterval {
        // 1 unit per minute
        units * TimeInterval(minutes: 1)
    }

    func startScan(_ callback: @escaping (MedtrumScanResult) -> Void) {
        bluetooth.startScan(callback)
    }

    func enactBolus(
        units: Double,
        activationType: LoopKit.BolusActivationType,
        completion: @escaping (LoopKit.PumpManagerError?) -> Void
    ) {
        let duration = estimatedDuration(toBolus: units)
        log.info("Enact bolus - \(units)U, \(duration)sec")

        guard let insulinType = state.insulinType else {
            log.error("Insulin type is nil...")
            completion(.configuration(.none))
            return
        }

        bluetooth.ensureConnected(autoDisconnect: false) { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                self.resetBolusState()

                completion(.communication(error))
                return
            }

            let bolusPacket = SetBolusPacket(bolusAmount: units)
            let writeResult = await self.bluetooth.write(bolusPacket)

            if case let .failure(error) = writeResult {
                self.log.error("Failed to write: \(error.localizedDescription)")
                self.resetBolusState()

                completion(.communication(error))
                return
            }

            let doseEntry = UnfinalizedDose(
                units: units,
                duration: duration,
                activationType: activationType,
                insulinType: insulinType
            )

            self.pumpDelegate.notify { delegate in
                guard let delegate = delegate else {
                    self.log.error("Dose could not be reported -> Missing delegate")
                    return
                }

                let dose = doseEntry.toDoseEntry(isMutable: true)
                let event = NewPumpEvent.bolus(
                    dose: dose,
                    units: dose.programmedUnits,
                    date: dose.startDate
                )
                delegate.pumpManager(
                    self,
                    hasNewPumpEvents: [event],
                    lastReconciliation: Date.now,
                    completion: { _ in }
                )
            }

            self.doseEntry = doseEntry
            self.doseReporter = MedtrumDoseProgressReporter(total: units)
            self.state.bolusState = .inProgress
            self.notifyStateDidChange()

            completion(nil)
        }
    }

    private func resetBolusState() {
        state.bolusState = .noBolus
        doseReporter = nil
        doseEntry = nil
        notifyStateDidChange()
    }

    func cancelBolus(completion: @escaping (LoopKit.PumpManagerResult<LoopKit.DoseEntry?>) -> Void) {
        log.info("Cancelling bolus...")

        let oldBolusState = state.bolusState
        state.bolusState = .canceling
        notifyStateDidChange()

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                self.state.bolusState = oldBolusState
                self.notifyStateDidChange()

                completion(.failure(.communication(error)))
                return
            }

            let packet = CancelBolusPacket()
            let result = await self.bluetooth.write(packet)

            if case let .failure(error) = result {
                self.log.error("Failed to cancel bolus: \(error.localizedDescription)")
                self.state.bolusState = oldBolusState
                self.notifyStateDidChange()

                completion(.failure(.communication(error)))
                return
            }

            self.log.info("Bolus cancelled!")
            self.state.bolusState = .noBolus
            self.notifyStateDidChange()

            guard let doseEntry = self.doseEntry else {
                completion(.success(nil))
                return
            }

            let dose = doseEntry.toDoseEntry()
            self.doseEntry = nil
            self.doseReporter = nil

            self.pumpDelegate.notify { delegate in
                delegate?.pumpManager(
                    self,
                    hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: dose.deliveredUnits ?? 0, date: dose.startDate)],
                    lastReconciliation: Date.now,
                    completion: { _ in }
                )
            }

            self.notifyStateDidChange()
            completion(.success(nil))
        }
    }

    func enactTempBasal(
        unitsPerHour: Double,
        for duration: TimeInterval,
        completion: @escaping (LoopKit.PumpManagerError?) -> Void
    ) {
        log.info("Setting temp basal at \(unitsPerHour)U/hr for \(duration) seconds...")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                completion(.communication(error))
                return
            }

            if case .tempBasal = self.state.basalState {
                // Need to cancel temp basal first before setting temp basal
                let cancelPacket = CancelTempBasalPacket()
                let cancelResult = await self.bluetooth.write(cancelPacket)

                if case let .failure(error) = cancelResult {
                    self.log.error("Failed to cancel temp basal: \(error.localizedDescription)")
                    completion(.communication(error))
                    return
                }

                self.state.basalState = .active
                self.state.basalStateSince = Date.now
                self.log.info("Cancelled temp basal!")
            }

            if duration < .ulpOfOne {
                // Need to cancel temp basal, but is already cancelled
                // Only need to report back to algorithm
                if let insulinType = self.state.insulinType {
                    let dose = DoseEntry.basal(rate: self.state.currentBaseBasalRate, insulinType: insulinType)
                    self.pumpDelegate.notify { delegate in
                        delegate?.pumpManager(
                            self,
                            hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)],
                            lastReconciliation: Date.now,
                            completion: { _ in }
                        )
                    }
                } else {
                    self.log.warning("No insulinType available...")
                }

                self.notifyStateDidChange()
                completion(nil)
                return
            }

            let packet = SetTempBasalPacket(rate: unitsPerHour, duration: duration)
            let tempBasalResult = await self.bluetooth.write(packet)

            if case let .failure(error) = tempBasalResult {
                self.log.error("Failed to set temp basal: \(error.localizedDescription)")
                completion(.communication(error))
                return
            }

            self.log.info("Set temp basal!")
            self.state.basalState = .tempBasal
            self.state.basalStateSince = Date.now
            self.state.tempBasalUnits = unitsPerHour
            self.state.tempBasalDuration = duration

            if let insulinType = self.state.insulinType {
                let dose = DoseEntry.tempBasal(absoluteUnit: unitsPerHour, duration: duration, insulinType: insulinType)
                self.pumpDelegate.notify { delegate in
                    delegate?.pumpManager(
                        self,
                        hasNewPumpEvents: [NewPumpEvent.tempBasal(dose: dose, units: unitsPerHour, duration: duration)],
                        lastReconciliation: Date.now,
                        completion: { _ in }
                    )
                }
            } else {
                self.log.warning("No insulinType available...")
            }

            self.notifyStateDidChange()
            completion(nil)
        }
    }

    func suspendDelivery(completion: @escaping ((any Error)?) -> Void) {
        log.info("Suspending delivery...")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                completion(error)
                return
            }

            // TODO: suspend needs to have configurable duration
            let packet = SuspendPumpPacket(duration: .minutes(120))
            let result = await self.bluetooth.write(packet)

            if case let .failure(error) = result {
                self.log.error("Failed to suspend delivery: \(error.localizedDescription)")
                completion(error)
                return
            }

            self.log.info("Delivery suspended for 120min!")

            let dose = DoseEntry.suspend()
            self.pumpDelegate.notify { delegate in
                delegate?.pumpManager(
                    self,
                    hasNewPumpEvents: [NewPumpEvent.suspend(dose: dose)],
                    lastReconciliation: Date.now,
                    completion: { _ in }
                )
            }

            self.state.basalState = .suspended
            self.state.basalStateSince = Date.now
            self.notifyStateDidChange()

            completion(nil)
        }
    }

    func resumeDelivery(completion: @escaping ((any Error)?) -> Void) {
        log.info("Suspending delivery...")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                completion(error)
                return
            }

            let packet = ResumePumpPacket()
            let response = await self.bluetooth.write(packet)

            if case let .failure(error) = response {
                self.log.error("Failed to resume delivery: \(error.localizedDescription)")
                completion(error)
                return
            }

            self.log.info("Resumed delivery!")

            if let insulinType = self.state.insulinType {
                let dose = DoseEntry.resume(insulinType: insulinType)
                self.pumpDelegate.notify { delegate in
                    delegate?.pumpManager(
                        self,
                        hasNewPumpEvents: [NewPumpEvent.resume(dose: dose)],
                        lastReconciliation: Date.now,
                        completion: { _ in }
                    )
                }
            } else {
                self.log.warning("No insulinType available...")
            }

            self.state.basalState = .active
            self.state.basalStateSince = Date.now
            self.notifyStateDidChange()

            completion(nil)
        }
    }

    func syncBasalRateSchedule(
        items: [LoopKit.RepeatingScheduleValue<Double>],
        completion: @escaping (Result<LoopKit.BasalRateSchedule, any Error>) -> Void
    ) {
        log.info("Sync-ing basal schedule...")
        guard let basalSchedule = DailyValueSchedule<Double>(dailyItems: items) else {
            completion(.failure(NSError(domain: "Basal schedule is empty...", code: -1)))
            return
        }

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            let schedule = BasalSchedule(entries: items)
            let packet = SetBasalProfilePacket(basalProfile: schedule.toData())
            let result = await self.bluetooth.write(packet)

            if case let .failure(error) = result {
                self.log.error("Failed to sync basal schedule: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            self.log.info("Basal schedule sync complete!")

            self.state.basalSchedule = schedule
            self.notifyStateDidChange()

            if let insulinType = self.state.insulinType {
                let dose = DoseEntry.basal(rate: self.state.currentBaseBasalRate, insulinType: insulinType)
                self.pumpDelegate.notify { delegate in
                    delegate?.pumpManager(
                        self,
                        hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)],
                        lastReconciliation: Date.now,
                        completion: { _ in }
                    )
                }
            } else {
                self.log.warning("No insulinType available...")
            }

            completion(.success(basalSchedule))
        }
    }

    func syncDeliveryLimits(
        limits _: LoopKit.DeliveryLimits,
        completion: @escaping (Result<LoopKit.DeliveryLimits, any Error>) -> Void
    ) {
        log
            .warning(
                "Skipping sync delivery limits (not supported by Medtrum). Limits are always -> maxBolus: 30u, maxBasal: 25u/hr"
            )
        completion(
            .success(
                DeliveryLimits(
                    maximumBasalRate: HKQuantity(
                        unit: HKUnit.internationalUnit().unitDivided(by: .hour()),
                        doubleValue: 25
                    ),
                    maximumBolus: HKQuantity(
                        unit: .internationalUnit(),
                        doubleValue: 30
                    )
                )
            )
        )
    }

    func primePatch(_ completion: @escaping (MedtrumPrimePatchResult) -> Void) {
        if state.pumpSN.isEmpty {
            // Need to scan for pump base first
            log.warning("No pump base known yet...")
            completion(.failure(error: .noKnownPumpBase))
            return
        }

        if state.sessionToken.isEmpty {
            // Patch has been disabled and thus a new session token is needed
            state.sessionToken = Crypto.genSessionToken()
            notifyStateDidChange()
        }

        bluetooth.ensureConnected(autoDisconnect: false) { error in
            if let error = error {
                self.log.error("Failed to connect to pump: \(error)")
                completion(.failure(error: .connectionFailure))
                return
            }

            guard self.state.pumpState.rawValue < PatchState.priming.rawValue else {
                self.log.info("Patch already activated!")
                completion(.success)
                return
            }

            let packet = PrimePacket()
            let primeResult = await self.bluetooth.write(packet)
            if case let .failure(error) = primeResult {
                self.log.error("Failed to start priming pump: \(error)")
                completion(.failure(error: .unknownError(reason: error.localizedDescription)))
                return
            }

            self.log.info("Priming has started!")
            completion(.success)
        }
    }

    func activatePatch(_ completion: @escaping (MedtrumActivatePatchResult) -> Void) {
        log.info("Activate patch pump...")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect to pump: \(error)")
                completion(.failure(error: .connectionFailure))
                return
            }

            guard self.state.pumpState.rawValue < PatchState.active.rawValue else {
                self.log.info("Patch already activated!")
                completion(.success)
                return
            }

            let packet = ActivatePacket(
                expirationTimer: self.state.expirationTimer,
                alarmSetting: self.state.alarmSetting,
                hourlyMaxInsulin: self.state.maxHourlyInsulin,
                dailyMaxInsulin: self.state.maxDailyInsulin,
                currentTDD: 0,
                basalProfile: self.state.basalSchedule.toData()
            )
            let result = await self.bluetooth.write(packet)
            switch result {
            case let .failure(error):
                self.log.error("Failed to activate pump: \(error)")
                completion(.failure(error: .unknownError(reason: error.localizedDescription)))
                return

            case let .success(data):
                guard let data = data as? ActivatePacketResponse else {
                    self.log.error("Failed to parse response...")
                    completion(.failure(error: .unknownError(reason: "Failed to parse response...")))
                    return
                }

                if self.state.expirationTimer == 1 {
                    NotificationManager.activatePatchExpiredNotification(after: self.state.notificationAfterActivation)
                }

                self.state.patchId = data.patchId
                self.state.patchActivatedAt = Date.now
                self.state.patchExpiresAt = Date.now.addingTimeInterval(.days(3)).addingTimeInterval(.hours(8))
                self.notifyStateDidChange()

                self.pumpDelegate.notify { delegate in
                    delegate?.pumpManagerPumpWasReplaced(self)
                }

                self.log.info("Patch activated!")
                completion(.success)
                return
            }
        }
    }

    func deactivatePatch(_ completion: @escaping (MedtrumDeactivatePatchResult) -> Void) {
        log.info("Deactivate patch pump...")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect to pump: \(error)")
                completion(.failure(error: .connectionFailure))
                return
            }

            let package = StopPatchPacket()
            let result = await self.bluetooth.write(package)
            if case let .failure(error) = result {
                self.log.error("Failed to deactivate pump: \(error)")
                completion(.failure(error: .unknownError(reason: error.localizedDescription)))
                return
            }

            self.state.previousPatch = PreviousPatch(
                patchId: self.state.patchId,
                lastStateRaw: self.state.pumpState.rawValue,
                lastSyncAt: self.state.lastSync,
                battery: self.state.battery,
                activatedAt: self.state.patchActivatedAt,
                deactivatedAt: Date.now
            )

            self.state.patchId = Data()
            self.state.pumpState = .none
            self.state.sessionToken = Data()
            self.notifyStateDidChange()

            self.log.info("Patch deactivated")
            completion(.success)
        }
    }

    func updatePatchSettings(completion: @escaping (MedtrumUpdatePatchResult) -> Void) {
        log.info("Update patch settings...")

        bluetooth.ensureConnected { error in
            if let error = error {
                self.log.error("Failed to connect to pump: \(error)")
                completion(.failure(error: .connectionFailure))
                return
            }

            let package = SetPatchPacket(
                alarmSettings: self.state.alarmSetting,
                hourlyMaxInsulin: self.state.maxHourlyInsulin,
                dailyMaxInsulin: self.state.maxDailyInsulin,
                expirationTimer: self.state.expirationTimer
            )
            let result = await self.bluetooth.write(package)
            if case let .failure(error) = result {
                self.log.error("Failed to update settings: \(error)")
                completion(.failure(error: .unknownError(reason: error.localizedDescription)))
                return
            }

            self.log.info("Patch settings updated!")
            completion(.success)
        }
    }

    func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    func notifyStateDidChange() {
        DispatchQueue.main.async {
            let status = self.status(self.state)
            let oldStatus = self.status(self.oldState)

            self.pumpDelegate.notify { delegate in
                delegate?.pumpManagerDidUpdateState(self)
                delegate?.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
            }

            self.statusObservers.forEach { observer in
                observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
            }

            self.oldState = MedtrumPumpState(rawValue: self.state.rawValue)
        }
    }

    func updateBolusProgress(delivered: Double, completed: Bool) {
        if let doseReporter = doseReporter {
            doseReporter.notify(deliveredUnits: delivered)
        }

        guard let doseEntry = self.doseEntry else {
            return
        }

        doseEntry.deliveredUnits = delivered

        if completed {
            state.bolusState = .noBolus
            notifyStateDidChange()

            let dose = doseEntry.toDoseEntry()
            self.doseEntry = nil
            doseReporter = nil

            pumpDelegate.notify { delegate in
                delegate?.pumpManager(
                    self,
                    hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: dose.deliveredUnits ?? 0, date: dose.startDate)],
                    lastReconciliation: Date.now,
                    completion: { _ in }
                )
            }
        }
    }
}
