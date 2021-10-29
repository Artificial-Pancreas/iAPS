//
//  MinimedPumpManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import RileyLinkKit
import RileyLinkBLEKit
import os.log

public protocol MinimedPumpManagerStateObserver: AnyObject {
    func didUpdatePumpManagerState(_ state: MinimedPumpManagerState)
}

public class MinimedPumpManager: RileyLinkPumpManager {
    public init(state: MinimedPumpManagerState, rileyLinkDeviceProvider: RileyLinkDeviceProvider, rileyLinkConnectionManager: RileyLinkConnectionManager? = nil, pumpOps: PumpOps? = nil) {
        self.lockedState = Locked(state)

        self.hkDevice = HKDevice(
            name: type(of: self).managerIdentifier,
            manufacturer: "Medtronic",
            model: state.pumpModel.rawValue,
            hardwareVersion: nil,
            firmwareVersion: state.pumpFirmwareVersion,
            softwareVersion: String(MinimedKitVersionNumber),
            localIdentifier: state.pumpID,
            udiDeviceIdentifier: nil
        )
        
        super.init(rileyLinkDeviceProvider: rileyLinkDeviceProvider, rileyLinkConnectionManager: rileyLinkConnectionManager)

        // Pump communication
        let idleListeningEnabled = state.pumpModel.hasMySentry && state.useMySentry
        self.pumpOps = pumpOps ?? PumpOps(pumpSettings: state.pumpSettings, pumpState: state.pumpState, delegate: self)

        self.rileyLinkDeviceProvider.idleListeningState = idleListeningEnabled ? MinimedPumpManagerState.idleListeningEnabledDefaults : .disabled
    }

    public required convenience init?(rawState: PumpManager.RawStateValue) {
        guard let state = MinimedPumpManagerState(rawValue: rawState),
            let connectionManagerState = state.rileyLinkConnectionManagerState else
        {
            return nil
        }
        
        let rileyLinkConnectionManager = RileyLinkConnectionManager(state: connectionManagerState)
        
        self.init(state: state, rileyLinkDeviceProvider: rileyLinkConnectionManager.deviceProvider, rileyLinkConnectionManager: rileyLinkConnectionManager)
        
        rileyLinkConnectionManager.delegate = self
    }

    public private(set) var pumpOps: PumpOps!

    // MARK: - PumpManager

    public let stateObservers = WeakSynchronizedSet<MinimedPumpManagerStateObserver>()

    public var state: MinimedPumpManagerState {
        return lockedState.value
    }
    private let lockedState: Locked<MinimedPumpManagerState>
    
    private func setState(_ changes: (_ state: inout MinimedPumpManagerState) -> Void) -> Void {
        return setStateWithResult(changes)
    }
    
    private func mutateState(_ changes: (_ state: inout MinimedPumpManagerState) -> Void) -> MinimedPumpManagerState {
        return setStateWithResult({ (state) -> MinimedPumpManagerState in
            changes(&state)
            return state
        })
    }
    
    private func setStateWithResult<ReturnType>(_ changes: (_ state: inout MinimedPumpManagerState) -> ReturnType) -> ReturnType {
        var oldValue: MinimedPumpManagerState!
        var returnValue: ReturnType!
        let newValue = lockedState.mutate { (state) in
            oldValue = state
            returnValue = changes(&state)
        }
        
        guard oldValue != newValue else {
            return returnValue
        }
        
        let recents = self.recents
        let oldStatus = status(for: oldValue, recents: recents)
        let newStatus = status(for: newValue, recents: recents)

        // PumpManagerStatus may have changed
        if oldStatus != newStatus
        {
            notifyStatusObservers(oldStatus: oldStatus)
        }
        
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManagerDidUpdateState(self)
        }
        stateObservers.forEach { (observer) in
            observer.didUpdatePumpManagerState(newValue)
        }
        return returnValue
    }
    

    /// Temporal state of the manager
    private var recents: MinimedPumpManagerRecents {
        get {
            return lockedRecents.value
        }
        set {
            let oldValue = recents
            let oldStatus = status
            lockedRecents.value = newValue

            // Battery percentage may have changed
            if oldValue.latestPumpStatusFromMySentry != newValue.latestPumpStatusFromMySentry ||
                oldValue.latestPumpStatus != newValue.latestPumpStatus
            {
                let oldBatteryPercentage = state.batteryPercentage
                let newBatteryPercentage: Double?

                // Persist the updated battery level
                if let status = newValue.latestPumpStatusFromMySentry {
                    newBatteryPercentage = Double(status.batteryRemainingPercent) / 100
                } else if let status = newValue.latestPumpStatus {
                    newBatteryPercentage = batteryChemistry.chargeRemaining(at: status.batteryVolts)
                } else {
                    newBatteryPercentage = nil
                }

                if oldBatteryPercentage != newBatteryPercentage {
                    setState { (state) in
                        state.batteryPercentage = newBatteryPercentage
                    }
                }
            }
            if oldStatus != status {
                notifyStatusObservers(oldStatus: oldStatus)
            }
        }
    }
    private let lockedRecents = Locked(MinimedPumpManagerRecents())

    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()

    private func notifyStatusObservers(oldStatus: PumpManagerStatus) {
        let status = self.status
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
        statusObservers.forEach { (observer) in
            observer.pumpManager(self, didUpdate: status, oldStatus: oldStatus)
        }
    }

    private let cgmDelegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()

    public let log = OSLog(category: "MinimedPumpManager")

    // MARK: - CGMManager

    private let hkDevice: HKDevice

    // MARK: - RileyLink Updates

    override public var rileyLinkConnectionManagerState: RileyLinkConnectionManagerState? {
        get {
            return state.rileyLinkConnectionManagerState
        }
        set {
            setState { (state) in
                state.rileyLinkConnectionManagerState = newValue
            }
        }
    }

    override public func device(_ device: RileyLinkDevice, didReceivePacket packet: RFPacket) {
        device.assertOnSessionQueue()

        guard let data = MinimedPacket(encodedData: packet.data)?.data,
            let message = PumpMessage(rxData: data),
            message.address.hexadecimalString == state.pumpID,
            case .mySentry = message.packetType
        else {
            return
        }

        switch message.messageBody {
        case let body as MySentryPumpStatusMessageBody:
            self.updatePumpStatus(body, from: device)
        case is MySentryAlertMessageBody, is MySentryAlertClearedMessageBody:
            break
        case let body:
            self.log.error("Unknown MySentry Message: %d: %{public}@", message.messageType.rawValue, body.txData.hexadecimalString)
        }
    }

    override public func deviceTimerDidTick(_ device: RileyLinkDevice) {
        pumpDelegate.notify { (delegate) in
            delegate?.pumpManagerBLEHeartbeatDidFire(self)
        }
    }

    public var rileyLinkBatteryAlertLevel: Int? {
        get {
            return state.rileyLinkBatteryAlertLevel
        }
        set {
            setState { state in
                state.rileyLinkBatteryAlertLevel = newValue
            }
        }
    }
    
    public override func device(_ device: RileyLinkDevice, didUpdateBattery level: Int) {
        let repeatInterval: TimeInterval = .hours(1)
        
        if let alertLevel = state.rileyLinkBatteryAlertLevel,
           level <= alertLevel,
           state.lastRileyLinkBatteryAlertDate.addingTimeInterval(repeatInterval) < Date()
        {
            self.setState { state in
                state.lastRileyLinkBatteryAlertDate = Date()
            }
            
            // HACK Alert. This is temporary for the 2.2.5 release. Dev and newer releases will use the new Loop Alert facility
            let notification = UNMutableNotificationContent()
            notification.body = String(format: LocalizedString("\"%1$@\" has a low battery", comment: "Format string for low battery alert body for RileyLink. (1: device name)"), device.name ?? "unnamed")
            notification.title = LocalizedString("Low RileyLink Battery", comment: "Title for RileyLink low battery alert")
            notification.sound = .default
            notification.categoryIdentifier = LoopNotificationCategory.loopNotRunning.rawValue
            notification.threadIdentifier = LoopNotificationCategory.loopNotRunning.rawValue
            let request = UNNotificationRequest(
                identifier: "batteryalert.rileylink",
                content: notification,
                trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - CustomDebugStringConvertible

    override public var debugDescription: String {
        return [
            "## MinimedPumpManager",
            "isPumpDataStale: \(isPumpDataStale)",
            "pumpOps: \(String(reflecting: pumpOps))",
            "recents: \(String(reflecting: recents))",
            "state: \(String(reflecting: state))",
            "status: \(String(describing: status))",
            "stateObservers.count: \(stateObservers.cleanupDeallocatedElements().count)",
            "statusObservers.count: \(statusObservers.cleanupDeallocatedElements().count)",
            super.debugDescription,
        ].joined(separator: "\n")
    }
}

extension MinimedPumpManager {
    /**
     Attempts to fix an extended communication failure between a RileyLink device and the pump

     - parameter device: The RileyLink device
     */
    private func troubleshootPumpComms(using device: RileyLinkDevice) {
        device.assertOnSessionQueue()

        // Ensuring timer tick is enabled will allow more tries to bring the pump data up-to-date.
        updateBLEHeartbeatPreference()

        // How long we should wait before we re-tune the RileyLink
        let tuneTolerance = TimeInterval(minutes: 14)

        let lastTuned = state.lastTuned ?? .distantPast

        if lastTuned.timeIntervalSinceNow <= -tuneTolerance {
            pumpOps.runSession(withName: "Tune pump", using: device) { (session) in
                do {
                    let scanResult = try session.tuneRadio(attempts: 1)
                    self.log.default("Device %{public}@ auto-tuned to %{public}@ MHz", device.name ?? "", String(describing: scanResult.bestFrequency))
                } catch let error {
                    self.log.error("Device %{public}@ auto-tune failed with error: %{public}@", device.name ?? "", String(describing: error))
                    self.rileyLinkDeviceProvider.deprioritize(device, completion: nil)
                    if let error = error as? LocalizedError {
                        self.pumpDelegate.notify { (delegate) in
                            delegate?.pumpManager(self, didError: PumpManagerError.communication(MinimedPumpManagerError.tuneFailed(error)))
                        }
                    }
                }
            }
        } else {
            rileyLinkDeviceProvider.deprioritize(device, completion: nil)
        }
    }

    /// - Throws: `PumpCommandError` specifying the failure sequence
    private func runSuspendResumeOnSession(suspendResumeState: SuspendResumeMessageBody.SuspendResumeState, session: PumpOpsSession, insulinType: InsulinType) throws {
        
        defer { self.recents.suspendEngageState = .stable }
        self.recents.suspendEngageState = suspendResumeState == .suspend ? .engaging : .disengaging

        try session.setSuspendResumeState(suspendResumeState)
        
        setState { (state) in
            let date = Date()
            switch suspendResumeState {
            case .suspend:
                state.suspendState = .suspended(date)
            case .resume:
                state.suspendState = .resumed(date)
            }
            
            if suspendResumeState == .suspend {
                let pumpModel = state.pumpModel
                state.unfinalizedBolus?.cancel(at: Date(), pumpModel: pumpModel)
                if let bolus = state.unfinalizedBolus {
                    state.pendingDoses.append(bolus)
                }
                state.unfinalizedBolus = nil
                
                state.pendingDoses.append(UnfinalizedDose(suspendStartTime: Date()))
            } else {
                state.pendingDoses.append(UnfinalizedDose(resumeStartTime: Date(), insulinType: insulinType))
            }
        }
    }

    private func setSuspendResumeState(state: SuspendResumeMessageBody.SuspendResumeState, insulinType: InsulinType, completion: @escaping (MinimedPumpManagerError?) -> Void) {
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(MinimedPumpManagerError.noRileyLink)
                return
            }
            
            let sessionName: String = {
                switch state {
                case .suspend:
                    return "Suspend Delivery"
                case .resume:
                    return "Resume Delivery"
                }
            }()

            self.pumpOps.runSession(withName: sessionName, using: device) { (session) in
                do {
                    try self.runSuspendResumeOnSession(suspendResumeState: state, session: session, insulinType: insulinType)
                    self.storePendingPumpEvents({ (error) in
                        completion(error)
                    })
                } catch let error {
                    self.troubleshootPumpComms(using: device)
                    completion(MinimedPumpManagerError.commsError(error as! PumpCommandError))
                }
            }
        }
    }

    /**
     Handles receiving a MySentry status message, which are only posted by MM x23 pumps.

     This message has two important pieces of info about the pump: reservoir volume and battery.

     Because the RileyLink must actively listen for these packets, they are not a reliable heartbeat. However, we can still use them to assert glucose data is current.

     - parameter status: The status message body
     - parameter device: The RileyLink that received the message
     */
    private func updatePumpStatus(_ status: MySentryPumpStatusMessageBody, from device: RileyLinkDevice) {
        device.assertOnSessionQueue()

        log.default("MySentry message received")

        var pumpDateComponents = status.pumpDateComponents
        var glucoseDateComponents = status.glucoseDateComponents

        let timeZone = state.timeZone
        pumpDateComponents.timeZone = timeZone
        glucoseDateComponents?.timeZone = timeZone

        checkRileyLinkBattery()

        // The pump sends the same message 3x, so ignore it if we've already seen it.
        guard status != recents.latestPumpStatusFromMySentry, let pumpDate = pumpDateComponents.date else {
            return
        }

        // Ignore status messages without some semblance of recency.
        guard abs(pumpDate.timeIntervalSinceNow) < .minutes(5) else {
            log.error("Ignored MySentry status due to date mismatch: %{public}@ in %{public}", String(describing: pumpDate), String(describing: timeZone))
            return
        }
        
        recents.latestPumpStatusFromMySentry = status

        switch status.glucose {
        case .active(glucose: let glucose):
            // Enlite data is included
            if let date = glucoseDateComponents?.date {
                let sample = NewGlucoseSample(
                    date: date,
                    quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose)),
                    isDisplayOnly: false,
                    wasUserEntered: false,
                    syncIdentifier: status.glucoseSyncIdentifier ?? UUID().uuidString,
                    device: self.device
                )

                cgmDelegate.notify { (delegate) in
                    delegate?.cgmManager(self, hasNew: .newData([sample]))
                }
            }
        case .off:
            // Enlite is disabled, so assert glucose from another source
            pumpDelegate.notify { (delegate) in
                delegate?.pumpManagerBLEHeartbeatDidFire(self)
            }
        default:
            // Anything else is an Enlite error
            // TODO: Provide info about status.glucose
            cgmDelegate.notify { (delegate) in
                delegate?.cgmManager(self, hasNew: .error(PumpManagerError.deviceState(nil)))
            }
        }
        
        // Sentry packets are sent in groups of 3, 5s apart. Wait 11s before allowing the loop data to continue to avoid conflicting comms.
        device.sessionQueueAsyncAfter(deadline: .now() + .seconds(11)) { [weak self] in
            self?.updateReservoirVolume(status.reservoirRemainingUnits, at: pumpDate, withTimeLeft: TimeInterval(minutes: Double(status.reservoirRemainingMinutes)))
        }
    }

    private func checkRileyLinkBattery() {
        rileyLinkDeviceProvider.getDevices { devices in
            for device in devices {
                device.updateBatteryLevel()
            }
        }
    }

    /**
     Store a new reservoir volume and notify observers of new pump data.

     - parameter units:    The number of units remaining
     - parameter date:     The date the reservoir was read
     - parameter timeLeft: The approximate time before the reservoir is empty
     */
    private func updateReservoirVolume(_ units: Double, at date: Date, withTimeLeft timeLeft: TimeInterval?) {
        // Must be called from the sessionQueue

        setState { (state) in
            state.lastReservoirReading = ReservoirReading(units: units, validAt: date)
        }

        pumpDelegate.notify { (delegate) in
            delegate?.pumpManager(self, didReadReservoirValue: units, at: date) { (result) in
                self.pumpManagerDelegateDidProcessReservoirValue(result)
            }
        }

        // New reservoir data means we may want to adjust our timer tick requirements
        updateBLEHeartbeatPreference()
    }

    /// Called on an unknown queue by the delegate
    private func pumpManagerDelegateDidProcessReservoirValue(_ result: Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) {
        switch result {
        case .failure:
            break
        case .success(let (_, _, areStoredValuesContinuous)):
            // Run a loop as long as we have fresh, reliable pump data.
            if state.preferredInsulinDataSource == .pumpHistory || !areStoredValuesContinuous {
                fetchPumpHistory { (error) in  // Can be centralQueue or sessionQueue
                    self.pumpDelegate.notify { (delegate) in
                        if let error = error as? PumpManagerError {
                            delegate?.pumpManager(self, didError: error)
                        }

                        if error == nil || areStoredValuesContinuous {
                            delegate?.pumpManagerRecommendsLoop(self)
                        }
                    }
                }
            } else {
                pumpDelegate.notify { (delegate) in
                    delegate?.pumpManagerRecommendsLoop(self)
                }
            }
        }
    }
    
    static func reconcilePendingDosesWith(_ events: [NewPumpEvent], reconciliationMappings: [Data:ReconciledDoseMapping], pendingDoses: [UnfinalizedDose]) ->
        (remainingEvents: [NewPumpEvent], reconciliationMappings: [Data:ReconciledDoseMapping], pendingDoses: [UnfinalizedDose]) {
            
        var newReconciliationMapping = reconciliationMappings
        
        var reconcilableEvents = events.filter { !newReconciliationMapping.keys.contains($0.raw) }
        
        // Pending doses can be matched to history events if start time difference is smaller than this
        let matchingTimeWindow = TimeInterval(minutes: 1)
        
        func addReconciliationMapping(startTime: Date, uuid: UUID, eventRaw: Data, index: Int) -> Void {
            let mapping = ReconciledDoseMapping(startTime: startTime, uuid: uuid, eventRaw: eventRaw)
            newReconciliationMapping[eventRaw] = mapping
        }
        
        // Reconcile any pending doses
        let allPending = pendingDoses.map { (dose) -> UnfinalizedDose in
            if let index = reconcilableEvents.firstMatchingIndex(for: dose, within: matchingTimeWindow) {
                let historyEvent = reconcilableEvents[index]
                addReconciliationMapping(startTime: dose.startTime, uuid: dose.uuid, eventRaw: historyEvent.raw, index: index)
                var reconciledDose = dose
                reconciledDose.reconcile(with: historyEvent)
                reconcilableEvents.remove(at: index)
                return reconciledDose
            }
            return dose
        }
            
        // Remove reconciled events
        let remainingPumpEvents = events.filter { (event) -> Bool in
            return newReconciliationMapping[event.raw] == nil
        }
        
        return (remainingEvents: remainingPumpEvents, reconciliationMappings: newReconciliationMapping, pendingDoses: allPending)
    }

    private func reconcilePendingDosesWith(_ events: [NewPumpEvent]) -> [NewPumpEvent] {
        // Must be called from the sessionQueue
        return setStateWithResult { (state) -> [NewPumpEvent] in
            let allPending = (state.pendingDoses + [state.unfinalizedTempBasal, state.unfinalizedBolus]).compactMap({ $0 })
            let result = MinimedPumpManager.reconcilePendingDosesWith(events, reconciliationMappings: state.reconciliationMappings, pendingDoses: allPending)
            state.lastReconciliation = Date()
            
            // Pending doses and reconciliation mappings will not be kept past this threshold
            let expirationCutoff = Date().addingTimeInterval(.hours(-12))
            
            state.reconciliationMappings = result.reconciliationMappings.filter { (key, value) -> Bool in
                return value.startTime >= expirationCutoff
            }
            
            state.unfinalizedBolus = nil
            state.unfinalizedTempBasal = nil
            state.pendingDoses = result.pendingDoses.filter { (dose) -> Bool in
                if !dose.isFinished {
                    switch dose.doseType {
                    case .bolus:
                        state.unfinalizedBolus = dose
                        return false
                    case .tempBasal:
                        state.unfinalizedTempBasal = dose
                        return false
                    default:
                        break
                    }
                }
                return dose.startTime >= expirationCutoff
            }
            
            if var runningTempBasal = state.unfinalizedTempBasal {
                // Look for following temp basal cancel event
                if let tempBasalCancellation = result.remainingEvents.first(where: { (event) -> Bool in
                    if let dose = event.dose,
                        dose.type == .tempBasal,
                        dose.startDate > runningTempBasal.startTime,
                        dose.startDate < runningTempBasal.finishTime,
                        dose.unitsPerHour == 0
                    {
                        return true
                    }
                    return false
                }) {
                    runningTempBasal.finishTime = tempBasalCancellation.date
                    state.unfinalizedTempBasal = runningTempBasal
                    state.suspendState = .resumed(tempBasalCancellation.date)
                }
            }
            return result.remainingEvents
        }
    }

    /// Polls the pump for new history events and passes them to the loop manager
    ///
    /// - Parameters:
    ///   - completion: A closure called once upon completion
    ///   - error: An error describing why the fetch and/or store failed
    private func fetchPumpHistory(_ completion: @escaping (_ error: Error?) -> Void) {
        guard let insulinType = insulinType else {
            completion(PumpManagerError.configuration(nil))
            return
        }
        
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink))
                return
            }
            
            self.pumpOps.runSession(withName: "Fetch Pump History", using: device) { (session) in
                do {
                    guard let startDate = self.pumpDelegate.call({ (delegate) in
                        return delegate?.startDateToFilterNewPumpEvents(for: self)
                    }) else {
                        preconditionFailure("pumpManagerDelegate cannot be nil")
                    }

                    // Include events up to a minute before startDate, since pump event time and pending event time might be off
                    let (historyEvents, model) = try session.getHistoryEvents(since: startDate.addingTimeInterval(.minutes(-1)))
                    
                    // Reconcile history with pending doses
                    let newPumpEvents = historyEvents.pumpEvents(from: model)
                    
                    // During reconciliation, some pump events may be reconciled as pending doses and removed. Remaining events should be annotated with current insulinType
                    let remainingHistoryEvents = self.reconcilePendingDosesWith(newPumpEvents).map { (event) -> NewPumpEvent in
                        return NewPumpEvent(
                            date: event.date,
                            dose: event.dose?.annotated(with: insulinType),
                            isMutable: event.isMutable,
                            raw: event.raw,
                            title: event.title,
                            type: event.type)
                    }

                    self.pumpDelegate.notify({ (delegate) in
                        guard let delegate = delegate else {
                            preconditionFailure("pumpManagerDelegate cannot be nil")
                        }
                        
                        let pendingEvents = (self.state.pendingDoses + [self.state.unfinalizedBolus, self.state.unfinalizedTempBasal]).compactMap({ $0?.newPumpEvent })

                        delegate.pumpManager(self, hasNewPumpEvents: remainingHistoryEvents + pendingEvents, lastReconciliation: self.lastReconciliation, completion: { (error) in
                            // Called on an unknown queue by the delegate
                            if error == nil {
                                self.recents.lastAddedPumpEvents = Date()
                                self.setState({ (state) in
                                    // Remove any pending doses that have been reconciled and are finished
                                    if let bolus = state.unfinalizedBolus, bolus.isReconciledWithHistory, bolus.isFinished {
                                        state.unfinalizedBolus = nil
                                    }
                                    if let tempBasal = state.unfinalizedTempBasal, tempBasal.isReconciledWithHistory, tempBasal.isFinished {
                                        state.unfinalizedTempBasal = nil
                                    }
                                    state.pendingDoses.removeAll(where: { (dose) -> Bool in
                                        if dose.isReconciledWithHistory && dose.isFinished {
                                            print("Removing stored, finished, reconciled dose: \(dose)")
                                        }
                                        return dose.isReconciledWithHistory && dose.isFinished
                                    })
                                })
                            }
                            completion(error)
                        })
                    })
                } catch let error {
                    self.troubleshootPumpComms(using: device)

                    completion(PumpManagerError.communication(error as? LocalizedError))
                }
            }
        }
    }

    private func storePendingPumpEvents(_ completion: @escaping (_ error: MinimedPumpManagerError?) -> Void) {
        // Must be called from the sessionQueue
        let events = (self.state.pendingDoses + [self.state.unfinalizedBolus, self.state.unfinalizedTempBasal]).compactMap({ $0?.newPumpEvent })
                
        log.debug("Storing pending pump events: %{public}@", String(describing: events))

        self.pumpDelegate.notify({ (delegate) in
            guard let delegate = delegate else {
                preconditionFailure("pumpManagerDelegate cannot be nil")
            }

            delegate.pumpManager(self, hasNewPumpEvents: events, lastReconciliation: self.lastReconciliation, completion: { (error) in
                // Called on an unknown queue by the delegate
                if let error = error {
                    self.log.error("Pump event storage failed: %{public}@", String(describing: error))
                    completion(MinimedPumpManagerError.storageFailure)
                } else {
                    completion(nil)
                }
            })

        })
    }

    // Safe to call from any thread
    private var isPumpDataStale: Bool {
        // How long should we wait before we poll for new pump data?
        let pumpStatusAgeTolerance = rileyLinkDeviceProvider.idleListeningEnabled ? TimeInterval(minutes: 6) : TimeInterval(minutes: 4)

        return isReservoirDataOlderThan(timeIntervalSinceNow: -pumpStatusAgeTolerance)
    }

    // Safe to call from any thread
    private func isReservoirDataOlderThan(timeIntervalSinceNow: TimeInterval) -> Bool {
        let state = self.state
        var lastReservoirDate = state.lastReservoirReading?.validAt ?? .distantPast

        // Look for reservoir data from MySentry that hasn't yet been written (due to 11-second imposed delay)
        if let sentryStatus = recents.latestPumpStatusFromMySentry {
            var components = sentryStatus.pumpDateComponents
            components.timeZone = state.timeZone

            lastReservoirDate = max(components.date ?? .distantPast, lastReservoirDate)
        }

        return lastReservoirDate.timeIntervalSinceNow <= timeIntervalSinceNow
    }

    private func updateBLEHeartbeatPreference() {
        // Must not be called on the delegate's queue
        rileyLinkDeviceProvider.timerTickEnabled = isPumpDataStale || pumpDelegate.call({ (delegate) -> Bool in
            return delegate?.pumpManagerMustProvideBLEHeartbeat(self) == true
        })
    }

    // MARK: - Configuration

    // MARK: Pump

    /// The user's preferred method of fetching insulin data from the pump
    public var preferredInsulinDataSource: InsulinDataSource {
        get {
            return state.preferredInsulinDataSource
        }
        set {
            setState { (state) in
                state.preferredInsulinDataSource = newValue
            }
        }
    }

    /// The pump battery chemistry, for voltage -> percentage calculation
    public var batteryChemistry: BatteryChemistryType {
        get {
            return state.batteryChemistry
        }
        set {
            setState { (state) in
                state.batteryChemistry = newValue
            }
        }
    }

    /// Whether to use MySentry packets on capable pumps:
    public var useMySentry: Bool {
        get {
            return state.useMySentry
        }
        set {
            let oldValue = state.useMySentry
            setState { (state) in
                state.useMySentry = newValue
            }
            if oldValue != newValue {
                let useIdleListening = state.pumpModel.hasMySentry && state.useMySentry
                self.rileyLinkDeviceProvider.idleListeningState = useIdleListening ? MinimedPumpManagerState.idleListeningEnabledDefaults : .disabled
            }
        }
    }

}


// MARK: - PumpManager
extension MinimedPumpManager: PumpManager {
    
    public static let managerIdentifier: String = "Minimed500"

    public static let localizedTitle = LocalizedString("Minimed 500/700 Series", comment: "Generic title of the minimed pump manager")

    public var localizedTitle: String {
        return String(format: LocalizedString("Minimed %@", comment: "Pump title (1: model number)"), state.pumpModel.rawValue)
    }

    /*
     It takes a MM pump about 40s to deliver 1 Unit while bolusing
     See: http://www.healthline.com/diabetesmine/ask-dmine-speed-insulin-pumps#3
     */
    private static let deliveryUnitsPerMinute = 1.5

    public var supportedBasalRates: [Double] {
        return state.pumpModel.supportedBasalRates
    }

    public var supportedBolusVolumes: [Double] {
        return state.pumpModel.supportedBolusVolumes
    }

    public var maximumBasalScheduleEntryCount: Int {
        return state.pumpModel.maximumBasalScheduleEntryCount
    }

    public var minimumBasalScheduleEntryDuration: TimeInterval {
        return state.pumpModel.minimumBasalScheduleEntryDuration
    }

    public var pumpRecordsBasalProfileStartEvents: Bool {
        return state.pumpModel.recordsBasalProfileStartEvents
    }

    public var pumpReservoirCapacity: Double {
        return Double(state.pumpModel.reservoirCapacity)
    }

    public var lastReconciliation: Date? {
        return state.lastReconciliation
    }
    
    public var insulinType: InsulinType? {
        get {
            return state.insulinType
        }
        set {
            setState { (state) in
                state.insulinType = newValue
            }
        }
    }
    
    private func status(for state: MinimedPumpManagerState, recents: MinimedPumpManagerRecents) -> PumpManagerStatus {
        let basalDeliveryState: PumpManagerStatus.BasalDeliveryState
        
        switch recents.suspendEngageState {
        case .engaging:
            basalDeliveryState = .suspending
        case .disengaging:
            basalDeliveryState = .resuming
        case .stable:
            switch recents.tempBasalEngageState {
            case .engaging:
                basalDeliveryState = .initiatingTempBasal
            case .disengaging:
                basalDeliveryState = .cancelingTempBasal
            case .stable:
                switch self.state.suspendState {
                case .suspended(let date):
                    basalDeliveryState = .suspended(date)
                case .resumed(let date):
                    if let tempBasal = state.unfinalizedTempBasal, !tempBasal.isFinished {
                        basalDeliveryState = .tempBasal(DoseEntry(tempBasal))
                    } else {
                        basalDeliveryState = .active(date)
                    }
                }
            }
        }
        
        let bolusState: PumpManagerStatus.BolusState
        
        switch recents.bolusEngageState {
        case .engaging:
            bolusState = .initiating
        case .disengaging:
            bolusState = .canceling
        case .stable:
            if let bolus = state.unfinalizedBolus, !bolus.isFinished {
                bolusState = .inProgress(DoseEntry(bolus))
            } else {
                bolusState = .noBolus
            }
        }
        
        return PumpManagerStatus(
            timeZone: state.timeZone,
            device: hkDevice,
            pumpBatteryChargeRemaining: state.batteryPercentage,
            basalDeliveryState: basalDeliveryState,
            bolusState: bolusState,
            insulinType: state.insulinType
        )
    }
    
    public var status: PumpManagerStatus {
        // Acquire the locks just once
        let state = self.state
        let recents = self.recents
        
        return status(for: state, recents: recents)
    }

    public var rawState: PumpManager.RawStateValue {
        return state.rawValue
    }

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get {
            return pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
        }
    }

    public var delegateQueue: DispatchQueue! {
        get {
            return pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
            cgmDelegate.queue = newValue
        }
    }

    // MARK: Methods

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        guard let insulinType = insulinType else {
            completion(PumpManagerError.configuration(nil))
            return
        }
        
        setSuspendResumeState(state: .suspend, insulinType: insulinType, completion: completion)
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        guard let insulinType = insulinType else {
            completion(PumpManagerError.configuration(nil))
            return
        }
        
        setSuspendResumeState(state: .resume, insulinType: insulinType, completion: completion)
    }

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        rileyLinkDeviceProvider.timerTickEnabled = isPumpDataStale || mustProvideBLEHeartbeat
    }

    /**
     Ensures pump data is current by either waking and polling, or ensuring we're listening to sentry packets.
     */
    public func ensureCurrentPumpData(completion: (() -> Void)?) {
        rileyLinkDeviceProvider.assertIdleListening(forcingRestart: true)

        guard isPumpDataStale else {
            completion?()
            return
        }

        log.default("Pump data is stale, fetching.")

        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                let error = PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)
                self.log.error("No devices found while fetching pump data")
                self.pumpDelegate.notify({ (delegate) in
                    delegate?.pumpManager(self, didError: error)
                    completion?()
                })
                return
            }

            self.pumpOps.runSession(withName: "Get Pump Status", using: device) { (session) in
                do {
                    defer { completion?() }
                    
                    let status = try session.getCurrentPumpStatus()
                    guard var date = status.clock.date else {
                        assertionFailure("Could not interpret a valid date from \(status.clock) in the system calendar")
                        throw PumpManagerError.configuration(MinimedPumpManagerError.noDate)
                    }

                    // Check if the clock should be reset
                    if abs(date.timeIntervalSinceNow) > .seconds(20) {
                        self.log.error("Pump clock is more than 20 seconds off. Resetting.")
                        self.pumpDelegate.notify({ (delegate) in
                            delegate?.pumpManager(self, didAdjustPumpClockBy: date.timeIntervalSinceNow)
                        })
                        try session.setTimeToNow()

                        guard let newDate = try session.getTime().date else {
                            throw PumpManagerError.configuration(MinimedPumpManagerError.noDate)
                        }

                        date = newDate
                    }

                    self.setState({ (state) in
                        if case .resumed = state.suspendState, status.suspended {
                            state.suspendState = .suspended(Date())
                        }
                    })

                    self.recents.latestPumpStatus = status

                    self.updateReservoirVolume(status.reservoir, at: date, withTimeLeft: nil)
                } catch let error {
                    self.log.error("Failed to fetch pump status: %{public}@", String(describing: error))
                    self.pumpDelegate.notify({ (delegate) in
                        delegate?.pumpManager(self, didError: PumpManagerError.communication(error as? LocalizedError))
                    })
                    self.troubleshootPumpComms(using: device)
                }
            }
        }
    }
    
    public func enactBolus(units: Double, automatic: Bool, completion: @escaping (PumpManagerResult<DoseEntry>) -> Void) {
        let enactUnits = roundToSupportedBolusVolume(units: units)

        guard enactUnits > 0 else {
            assertionFailure("Invalid zero unit bolus")
            return
        }
        
        guard let insulinType = insulinType else {
            completion(.failure(.configuration(nil)))
            return
        }


        pumpOps.runSession(withName: "Bolus", using: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in

            guard let session = session else {
                completion(.failure(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }

            if let unfinalizedBolus = self.state.unfinalizedBolus {
                guard unfinalizedBolus.isFinished else {
                    completion(.failure(PumpManagerError.deviceState(MinimedPumpManagerError.bolusInProgress)))
                    return
                }
                
                self.setState({ (state) in
                    state.pendingDoses.append(unfinalizedBolus)
                    state.unfinalizedBolus = nil
                })
            }

            self.recents.bolusEngageState = .engaging

            // If we don't have recent pump data, or the pump was recently rewound, read new pump data before bolusing.
            if self.isReservoirDataOlderThan(timeIntervalSinceNow: .minutes(-6)) {
                do {
                    let reservoir = try session.getRemainingInsulin()

                    self.pumpDelegate.notify({ (delegate) in
                        delegate?.pumpManager(self, didReadReservoirValue: reservoir.units, at: reservoir.clock.date!) { _ in
                            // Ignore result
                        }
                    })
                } catch let error {
                    self.recents.bolusEngageState = .stable
                    self.log.error("Failed to fetch pump status: %{public}@", String(describing: error))
                    completion(.failure(PumpManagerError.communication(error as? LocalizedError)))
                    return
                }
            }

            if case .suspended = self.state.suspendState {
                do {
                    try self.runSuspendResumeOnSession(suspendResumeState: .resume, session: session, insulinType: insulinType)
                } catch let error {
                    self.recents.bolusEngageState = .stable
                    self.log.error("Failed to resume pump for bolus: %{public}@", String(describing: error))
                    completion(.failure(PumpManagerError.communication(error as? LocalizedError)))
                    return
                }
            }

            let deliveryTime = self.state.pumpModel.bolusDeliveryTime(units: enactUnits)

            do {
                try session.setNormalBolus(units: enactUnits)

                // Between bluetooth and the radio and firmware, about 2s on average passes before we start tracking
                let commsOffset = TimeInterval(seconds: -2)
                let doseStart = Date().addingTimeInterval(commsOffset)

                let dose = UnfinalizedDose(bolusAmount: enactUnits, startTime: doseStart, duration: deliveryTime, insulinType: insulinType, automatic: automatic)
                self.setState({ (state) in
                    state.unfinalizedBolus = dose
                })
                self.recents.bolusEngageState = .stable

                self.storePendingPumpEvents({ (error) in
                    completion(.success(DoseEntry(dose)))
                })
            } catch let error {
                self.log.error("Failed to bolus: %{public}@", String(describing: error))
                self.recents.bolusEngageState = .stable
                completion(.failure(PumpManagerError.communication(error as? LocalizedError)))
            }
        }
    }

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        
        guard let insulinType = insulinType else {
            completion(.failure(.configuration(nil)))
            return
        }

        self.recents.bolusEngageState = .disengaging
        setSuspendResumeState(state: .suspend, insulinType: insulinType) { (error) in
            self.recents.bolusEngageState = .stable
            if let error = error {
                completion(.failure(PumpManagerError.communication(error)))
            } else {
                completion(.success(nil))
            }
        }
    }
    
    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerResult<DoseEntry>) -> Void) {
        guard let insulinType = insulinType else {
            completion(.failure(.configuration(nil)))
            return
        }

        pumpOps.runSession(withName: "Set Temp Basal", using: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            guard let session = session else {
                completion(.failure(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }
            
            self.recents.tempBasalEngageState = .engaging

            let result = session.setTempBasal(unitsPerHour, duration: duration)
            
            switch result {
            case .success(let response):
                let now = Date()
                let endDate = now.addingTimeInterval(response.timeRemaining)
                let startDate = endDate.addingTimeInterval(-duration)

                let dose = UnfinalizedDose(tempBasalRate: unitsPerHour, startTime: startDate, duration: duration, insulinType: insulinType)
                
                self.recents.tempBasalEngageState = .stable
                
                let isResumingScheduledBasal = duration < .ulpOfOne

                // If we were successful, then we know we aren't suspended
                self.setState({ (state) in
                    if case .suspended = state.suspendState {
                        state.suspendState = .resumed(startDate)
                    } else if isResumingScheduledBasal {
                        state.suspendState = .resumed(startDate)
                    }
                    
                    let pumpModel = state.pumpModel
                    
                    state.unfinalizedTempBasal?.cancel(at: startDate, pumpModel: pumpModel)
                    if let previousTempBasal = state.unfinalizedTempBasal {
                        state.pendingDoses.append(previousTempBasal)
                    }
                    
                    if isResumingScheduledBasal {
                        state.unfinalizedTempBasal = nil
                    } else {
                        state.unfinalizedTempBasal = dose
                    }
                })

                self.storePendingPumpEvents({ (error) in
                    completion(.success(DoseEntry(dose)))
                })

                // Continue below
            case .failure(let error):
                completion(.failure(PumpManagerError.communication(error)))

                // If we got a command-refused error, we might be suspended or bolusing, so update the state accordingly
                if case .arguments(.pumpError(.commandRefused)) = error {
                    do {
                        let status = try session.getCurrentPumpStatus()
                        self.setState({ (state) in
                            if case .resumed = state.suspendState, status.suspended {
                                state.suspendState = .suspended(Date())
                            }
                        })
                        self.recents.latestPumpStatus = status
                    } catch {
                        self.log.error("Post-basal suspend state fetch failed: %{public}@", String(describing: error))
                    }
                }
                self.recents.tempBasalEngageState = .stable
                return
            }

            do {
                // If we haven't fetched history in a while, our preferredInsulinDataSource is probably .reservoir, so
                // let's take advantage of the pump radio being on.
                if self.recents.lastAddedPumpEvents.timeIntervalSinceNow < .minutes(-4) {
                    let clock = try session.getTime()
                    // Check if the clock should be reset
                    if let date = clock.date, abs(date.timeIntervalSinceNow) > .seconds(20) {
                        self.log.error("Pump clock is more than 20 seconds off. Resetting.")
                        self.pumpDelegate.notify({ (delegate) in
                            delegate?.pumpManager(self, didAdjustPumpClockBy: date.timeIntervalSinceNow)
                        })
                        try session.setTimeToNow()
                    }

                    self.fetchPumpHistory { (error) in
                        if let error = error {
                            self.log.error("Post-basal history fetch failed: %{public}@", String(describing: error))
                        }
                    }
                }
            } catch {
                self.log.error("Post-basal time sync failed: %{public}@", String(describing: error))
            }
        }
    }

    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        if let bolus = self.state.unfinalizedBolus, !bolus.isFinished {
            return MinimedDoseProgressEstimator(dose: DoseEntry(bolus), pumpModel: state.pumpModel, reportingQueue: dispatchQueue)
        }
        return nil
    }
    
    public func setMaximumTempBasalRate(_ rate: Double) { }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        pumpOps.runSession(withName: "Save Basal Profile", using: rileyLinkDeviceProvider.firstConnectedDevice) { (session) in
            guard let session = session else {
                completion(.failure(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }

            do {
                let newSchedule = BasalSchedule(repeatingScheduleValues: scheduleItems)
                try session.setBasalSchedule(newSchedule, for: .standard)

                completion(.success(BasalRateSchedule(dailyItems: scheduleItems, timeZone: session.pump.timeZone)!))
            } catch let error {
                self.log.error("Save basal profile failed: %{public}@", String(describing: error))
                completion(.failure(error))
            }
        }
    }
}

extension MinimedPumpManager: PumpOpsDelegate {
    public func pumpOps(_ pumpOps: PumpOps, didChange state: PumpState) {
        setState { (pumpManagerState) in
            pumpManagerState.pumpState = state
        }
    }
}

extension MinimedPumpManager: CGMManager {
    public var device: HKDevice? {
        return hkDevice
    }

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return cgmDelegate.delegate
        }
        set {
            cgmDelegate.delegate = newValue
        }
    }

    public var shouldSyncToRemoteService: Bool {
        return true
    }

    public var providesBLEHeartbeat: Bool {
        return false
    }

    public var managedDataInterval: TimeInterval? {
        return nil
    }

    public var glucoseDisplay: GlucoseDisplayable? {
        return recents.sensorState
    }
    
    public var cgmStatus: CGMManagerStatus {
        return CGMManagerStatus(hasValidSensorSession: hasValidSensorSession)
    }
    
    public var hasValidSensorSession: Bool {
        // No tracking of session available
        return true
    }

    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMReadingResult) -> Void) {
        rileyLinkDeviceProvider.getDevices { (devices) in
            guard let device = devices.firstConnected else {
                completion(.error(PumpManagerError.connection(MinimedPumpManagerError.noRileyLink)))
                return
            }

            let latestGlucoseDate = self.cgmDelegate.call({ (delegate) -> Date in
                return delegate?.startDateToFilterNewData(for: self) ?? Date(timeIntervalSinceNow: TimeInterval(hours: -24))
            })

            guard latestGlucoseDate.timeIntervalSinceNow <= TimeInterval(minutes: -4.5) else {
                completion(.noData)
                return
            }

            self.pumpOps.runSession(withName: "Fetch Enlite History", using: device) { (session) in
                do {
                    let events = try session.getGlucoseHistoryEvents(since: latestGlucoseDate.addingTimeInterval(.minutes(1)))

                    if let latestSensorEvent = events.compactMap({ $0.glucoseEvent as? RelativeTimestampedGlucoseEvent }).last {
                        self.recents.sensorState = EnliteSensorDisplayable(latestSensorEvent)
                    }

                    let unit = HKUnit.milligramsPerDeciliter
                    let glucoseValues: [NewGlucoseSample] = events
                        // TODO: Is the { $0.date > latestGlucoseDate } filter duplicative?
                        .filter({ $0.glucoseEvent is SensorValueGlucoseEvent && $0.date > latestGlucoseDate })
                        .map {
                            let glucoseEvent = $0.glucoseEvent as! SensorValueGlucoseEvent
                            let quantity = HKQuantity(unit: unit, doubleValue: Double(glucoseEvent.sgv))
                            return NewGlucoseSample(date: $0.date, quantity: quantity, isDisplayOnly: false, wasUserEntered: false, syncIdentifier: glucoseEvent.glucoseSyncIdentifier ?? UUID().uuidString, device: self.device)
                    }

                    completion(.newData(glucoseValues))
                } catch let error {
                    completion(.error(error))
                }
            }
        }
    }
}

// MARK: - AlertResponder implementation
extension MinimedPumpManager {
    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier) { }
}

// MARK: - AlertSoundVendor implementation
extension MinimedPumpManager {
    public func getSoundBaseURL() -> URL? { return nil }
    public func getSounds() -> [Alert.Sound] { return [] }
}

