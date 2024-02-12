//
//  DanaKitPumpManager.swift
//  DanaKit
//
//  Based on OmniKit/PumpManager/OmnipodPumpManager.swift
//  Created by Pete Schwamb on 8/4/18.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import UserNotifications
import os.log
import CoreBluetooth

private enum ConnectionResult {
    case success
    case failure
}

public protocol StateObserver: AnyObject {
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _ oldState: DanaKitPumpManagerState)
    func deviceScanDidUpdate(_ device: DanaPumpScan)
}

public class DanaKitPumpManager: DeviceManager {
    private static var bluetoothManager = BluetoothManager()
    
    private var oldState: DanaKitPumpManagerState
    public var state: DanaKitPumpManagerState
    public var rawState: PumpManager.RawStateValue {
        return state.rawValue
    }
    
    public static let pluginIdentifier: String = "Dana" // use a single token to make parsing log files easier
    public let managerIdentifier: String = "Dana"
    
    public let localizedTitle = LocalizedString("Dana-i/RS", comment: "Generic title of the DanaKit pump manager")
    
    public init(state: DanaKitPumpManagerState, dateGenerator: @escaping () -> Date = Date.init) {
        self.state = state
        self.oldState = DanaKitPumpManagerState(rawValue: state.rawValue)
        
        DanaKitPumpManager.bluetoothManager.pumpManagerDelegate = self
    }
    
    public required convenience init?(rawState: PumpManager.RawStateValue) {
        self.init(state: DanaKitPumpManagerState(rawValue: rawState))
    }
    
    private let log = OSLog(category: "DanaKitPumpManager")
    private let pumpDelegate = WeakSynchronizedDelegate<PumpManagerDelegate>()
    
    private let statusObservers = WeakSynchronizedSet<PumpManagerStatusObserver>()
    private let stateObservers = WeakSynchronizedSet<StateObserver>()
    private let scanDeviceObservers = WeakSynchronizedSet<StateObserver>()
    
    private var doseReporter: DanaKitDoseProgressReporter?
    private var doseEntry: UnfinalizedDose?
    private let basalProfileNumber: UInt8 = 1
    
    public var isOnboarded: Bool {
        self.state.isOnBoarded
    }
    
    public var currentBaseBasalRate: Double = 0
    public var status: PumpManagerStatus {
        return self.status(state)
    }
    
    public var debugDescription: String {
        let lines = [
            "## DanaKitPumpManager",
            state.debugDescription
        ]
        return lines.joined(separator: "\n")
    }
    
    public func connect(_ peripheral: CBPeripheral, _ completion: @escaping (Error?) -> Void) {
        DanaKitPumpManager.bluetoothManager.connect(peripheral, completion)
    }
    
    public func disconnect(_ peripheral: CBPeripheral) {
        DanaKitPumpManager.bluetoothManager.disconnect(peripheral)
        self.state.resetState()
    }
    
    public func startScan() throws {
        try DanaKitPumpManager.bluetoothManager.startScan()
    }
    
    public func stopScan() {
        DanaKitPumpManager.bluetoothManager.stopScan()
    }
    
    // Not persisted
    var provideHeartbeat: Bool = false

    private var lastHeartbeat: Date = .distantPast
    
    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        provideHeartbeat = mustProvideBLEHeartbeat
    }

    private func issueHeartbeatIfNeeded() {
        if self.provideHeartbeat, Date().timeIntervalSince(lastHeartbeat) > 2 * 60 {
            self.pumpDelegate.notify { (delegate) in
                delegate?.pumpManagerBLEHeartbeatDidFire(self)
            }
            self.lastHeartbeat = Date()
        }
    }
}

extension DanaKitPumpManager: PumpManager {
    public static var onboardingMaximumBasalScheduleEntryCount: Int {
        return 24
    }
    
    public static var onboardingSupportedBasalRates: [Double] {
        // 0.05 units for rates between 0.00-3U/hr
        // 0 U/hr is a supported scheduled basal rate
        return (0...60).map { Double($0) / 20 }
    }
    
    public static var onboardingSupportedBolusVolumes: [Double] {
        // 0.10 units for rates between 0.10-30U
        // 0 is not a supported bolus volume
        return (1...300).map { Double($0) / 10 }
    }
    
    public static var onboardingSupportedMaximumBolusVolumes: [Double] {
        return DanaKitPumpManager.onboardingSupportedBolusVolumes
    }
    
    public var delegateQueue: DispatchQueue! {
        get {
            return pumpDelegate.queue
        }
        set {
            pumpDelegate.queue = newValue
        }
    }
    
    public var supportedBasalRates: [Double] {
        return DanaKitPumpManager.onboardingSupportedBasalRates
    }
    
    public var supportedBolusVolumes: [Double] {
        return DanaKitPumpManager.onboardingSupportedBolusVolumes
    }
    
    public var supportedMaximumBolusVolumes: [Double] {
        // 0.05 units for rates between 0.05-30U
        // 0 is not a supported bolus volume
        return DanaKitPumpManager.onboardingSupportedBolusVolumes
    }
    
    public var maximumBasalScheduleEntryCount: Int {
        return DanaKitPumpManager.onboardingMaximumBasalScheduleEntryCount
    }
    
    public var minimumBasalScheduleEntryDuration: TimeInterval {
        // One per hour
        return TimeInterval(60 * 60)
    }
    
    public func roundToSupportedBolusVolume(units: Double) -> Double {
        // We do support rounding a 0 U volume to 0
        return supportedBolusVolumes.last(where: { $0 <= units }) ?? 0
    }
    
    public var pumpManagerDelegate: LoopKit.PumpManagerDelegate? {
        get {
            return pumpDelegate.delegate
        }
        set {
            pumpDelegate.delegate = newValue
        }
    }
    
    public var pumpRecordsBasalProfileStartEvents: Bool {
        return false
    }
    
    public var pumpReservoirCapacity: Double {
        return Double(self.state.reservoirLevel)
    }
    
    public var lastSync: Date? {
        return self.state.lastStatusDate
    }
    
    private func status(_ state: DanaKitPumpManagerState) -> LoopKit.PumpManagerStatus {
        // Check if temp basal is expired, before constructing basalDeliveryState
        if self.state.basalDeliveryOrdinal == .tempBasal && self.state.basalDeliveryDate + (self.state.tempBasalDuration ?? 0) > Date.now {
            self.state.basalDeliveryOrdinal = .active
            self.state.basalDeliveryDate = Date.now
            self.state.tempBasalDuration = nil
            self.state.tempBasalDuration = nil
            
            DispatchQueue.main.async {
                self.notifyStateDidChange()
            }
        }
        
        return PumpManagerStatus(
            timeZone: TimeZone.current,
            device: device(),
            pumpBatteryChargeRemaining: state.batteryRemaining / 100,
            basalDeliveryState: state.basalDeliveryState,
            bolusState: bolusState(self.state.bolusState),
            insulinType: state.insulinType
        )
    }
    
    private func bolusState(_ bolusState: BolusState) -> PumpManagerStatus.BolusState {
        switch bolusState {
        case .noBolus:
            return .noBolus
        case .initiating:
            return .initiating
        case .canceling:
            return .canceling
        case .inProgress:
            if let dose = self.doseEntry?.toDoseEntry() {
                return .inProgress(dose)
            }
            
            return .noBolus
        }
    }
    
    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        log.default("%{public}@: Syncing pump data", #function)
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection failure", #function)
                completion?(nil)
                return
            case .success:
                Task {
                    let events = await self.syncHistory()
                    self.state.lastStatusDate = Date()
                    
                    self.disconnect()
 
                    DispatchQueue.main.async {
                        self.issueHeartbeatIfNeeded()
                        self.notifyStateDidChange()
                        
                        self.pumpDelegate.notify { (delegate) in
                            delegate?.pumpManager(self, hasNewPumpEvents: events, lastReconciliation: Date.now, completion: { _ in })
                            delegate?.pumpManager(self, didReadReservoirValue: self.state.reservoirLevel, at: Date.now, completion: { _ in })
                            delegate?.pumpManagerDidUpdateState(self)
                        }
                    }
                    
                    completion?(Date.now)
                }
            }
        }
    }
    
    private func syncHistory() async -> [NewPumpEvent] {
        var hasHistoryModeBeenActivate = false
        do {
            let activateHistoryModePacket = generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode(mode: 1))
            let activateHistoryModeResult = try await DanaKitPumpManager.bluetoothManager.writeMessage(activateHistoryModePacket)
            guard activateHistoryModeResult.success else {
                return []
            }
            
            hasHistoryModeBeenActivate = true
            
            let fetchHistoryPacket = generatePacketHistoryAll(options: PacketHistoryBase(from: state.lastStatusDate))
            let fetchHistoryResult = try await DanaKitPumpManager.bluetoothManager.writeMessage(fetchHistoryPacket)
            guard activateHistoryModeResult.success else {
                return []
            }
            
            let deactivateHistoryModePacket = generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode(mode: 0))
            let _ = try await DanaKitPumpManager.bluetoothManager.writeMessage(deactivateHistoryModePacket)

            return (fetchHistoryResult.data as! [HistoryItem]).map({ item in
                switch(item.code) {
                case HistoryCode.RECORD_TYPE_ALARM:
                    return NewPumpEvent(date: item.timestamp, dose: nil, raw: item.raw, title: "Alarm: \(getAlarmMessage(param8: item.alarm))", type: .alarm, alarmType: PumpAlarmType.fromParam8(item.alarm))
                
                case HistoryCode.RECORD_TYPE_BOLUS:
                    // If we find a bolus here, we assume that is hasnt been synced to Loop
                    return NewPumpEvent.bolus(
                        dose: DoseEntry.bolus(units: item.value!, deliveredUnits: item.value!, duration: item.durationInMin! * 60, activationType: .manualNoRecommendation, insulinType: self.state.insulinType!, startDate: item.timestamp),
                        units: item.value!)
                    
                case HistoryCode.RECORD_TYPE_SUSPEND:
                    if item.value! == 1 {
                        return NewPumpEvent.suspend(dose: DoseEntry.suspend(suspendDate: item.timestamp))
                    } else {
                        return NewPumpEvent.resume(dose: DoseEntry.resume(insulinType: self.state.insulinType!, resumeDate: item.timestamp))
                    }
                    
                case HistoryCode.RECORD_TYPE_PRIME:
                    return NewPumpEvent(date: item.timestamp, dose: nil, raw: item.raw, title: "Prime \(item.value!)U", type: .prime, alarmType: nil)
                    
                case HistoryCode.RECORD_TYPE_REFILL:
                    return NewPumpEvent(date: item.timestamp, dose: nil, raw: item.raw, title: "Rewind \(item.value!)U", type: .rewind, alarmType: nil)
                    
                case HistoryCode.RECORD_TYPE_TEMP_BASAL:
                    // TODO: Find a way to convert % to U/hr
                    return nil
                    
                default:
                    return nil
                }
            })
            // Filter nil values
            .compactMap{$0}
        } catch {
            log.error("%{public}@: Failed to sync history. Error: %{public}@", #function, error.localizedDescription)
            if hasHistoryModeBeenActivate {
                do {
                    let deactivateHistoryModePacket = generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode(mode: 0))
                    let _ = try await DanaKitPumpManager.bluetoothManager.writeMessage(deactivateHistoryModePacket)
                } catch {}
            }
            return []
        }
    }
    
    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        return doseReporter
    }
    
    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        switch(self.state.bolusSpeed) {
        case .speed12:
            return units / 12 * 60
        case .speed30:
            return units / 30 * 60
        case .speed60:
            return units // / 60 * 60
        }
    }
    
    public func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (PumpManagerError?) -> Void) {
        log.default("%{public}@: Enact bolus", #function)
        
        self.state.bolusState = .initiating
        self.notifyStateDidChange()
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                self.state.bolusState = .noBolus
                self.notifyStateDidChange()
                
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    guard !self.state.isPumpSuspended else {
                        self.state.bolusState = .noBolus
                        self.notifyStateDidChange()
                        self.disconnect()
                        
                        self.log.error("%{public}@: Pump is suspended", #function)
                        completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpSuspended))
                        return
                    }
                    
                    do {
                        let packet = generatePacketBolusStart(options: PacketBolusStart(amount: units, speed: self.state.bolusSpeed))
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        guard result.success else {
                            self.state.bolusState = .noBolus
                            self.notifyStateDidChange()
                            self.disconnect()
                            
                            completion(PumpManagerError.uncertainDelivery)
                            return
                        }
                        
                        let duration = self.estimatedDuration(toBolus: units)
                        self.doseEntry = UnfinalizedDose(units: units, duration: duration, activationType: activationType, insulinType: self.state.insulinType!)
                        self.doseReporter = DanaKitDoseProgressReporter(total: units)
                        
                        self.state.lastStatusDate = Date()
                        self.state.bolusState = .inProgress
                        self.notifyStateDidChange()
                        
                        // To ensure the bolus state doesnt block loop, we set a timer to remove the blocking bolusstate
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            self.state.bolusState = .noBolus
                            self.notifyStateDidChange()
                        }
                        
                        completion(nil)
                    } catch {
                        self.state.bolusState = .noBolus
                        self.notifyStateDidChange()
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to do bolus. Error: %{public}@", #function, error.localizedDescription)
                        completion(PumpManagerError.connection(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                }
            }
        }
    }
    
    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        log.default("%{public}@: Cancel bolus", #function)
        let oldBolusState = self.state.bolusState
        self.state.bolusState = .canceling
        self.notifyStateDidChange()
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                self.state.bolusState = oldBolusState
                self.notifyStateDidChange()
                
                completion(.failure(PumpManagerError.connection(DanaKitPumpManagerError.noConnection)))
                return
            case .success:
                Task {
                    do {
                        let packet = generatePacketBolusStop()
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        
                        if (!result.success) {
                            self.state.bolusState = oldBolusState
                            self.notifyStateDidChange()
                            
                            completion(.failure(PumpManagerError.communication(nil)))
                            return
                        }
                        
                        // Increase status update date, to prevent double bolus entries
                        self.state.lastStatusDate = Date()
                        self.state.bolusState = .noBolus
                        self.notifyStateDidChange()
                        
                        completion(.success(nil))
                        return
                    } catch {
                        self.state.bolusState = oldBolusState
                        self.notifyStateDidChange()
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to cancel bolus. Error: %{public}@", #function, error.localizedDescription)
                        completion(.failure(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription))))
                    }
                }
            }
        }
    }
    
    /// NOTE: There are 2 ways to set a temp basal:
    /// - The normal way (which only accepts full hours and percentages)
    /// - A short APS-special temp basal command (which only accepts 15 min or 30 min
    /// Currently, the above is implemented with a simpel U/hr -> % calculator
    /// TODO: Finetune the calculator and find a way to deal with 90 min temp basal i.e.
    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        log.default("%{public}@: Enact temp basal", #function)
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Conenction error", #function)
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    guard !self.state.isPumpSuspended else {
                        self.log.error("%{public}@: Pump is suspended", #function)
                        self.disconnect()
                        completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpSuspended))
                        return
                    }
                    
                    do {
                        
                        if self.state.isTempBasalInProgress {
                            let packet = generatePacketBasalCancelTemporary()
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            
                            guard result.success else {
                                self.disconnect()
                                self.log.error("%{public}@: Could not cancel old temp basal (full hour)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Could not cancel old temp basal (full hour)")))
                                return
                            }
                        }
                        
                        if (duration < .ulpOfOne) {
                            self.disconnect()
                            
                            self.state.basalDeliveryOrdinal = .active
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = nil
                            self.state.tempBasalDuration = nil
                            self.notifyStateDidChange()
                            
                            let dose = DoseEntry.basal(rate: self.currentBaseBasalRate, insulinType: self.state.insulinType!)
                            self.pumpDelegate.notify { (delegate) in
                                delegate?.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)], lastReconciliation: Date.now, completion: { _ in })
                            }
                            
                            self.log.default("%{public}@: Succesfully cancelled temp basal", #function)
                            completion(nil)
                            
                        } else if duration == 900 {
                            // 15 min. Only basal boosts allowed here
                            let percentage = self.absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            guard let percentage = percentage else {
                                self.disconnect()
                                self.log.error("%{public}@: Basal schedule is not available... (15 min)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Basal schedule is not available... (15 min)")))
                                return
                            }
                            
                            let packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage, duration: .min15))
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            self.disconnect()
                            
                            guard result.success else {
                                self.log.error("%{public}@: Pump rejected command (15 min)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump rejected command (15 min)")))
                                return
                            }
                            
                            let dose = DoseEntry.tempBasal(absoluteUnit: unitsPerHour, duration: duration, insulinType: self.state.insulinType!)
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = duration
                            self.notifyStateDidChange()
                            
                            self.pumpDelegate.notify { (delegate) in
                                delegate?.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.tempBasal(dose: dose, units: unitsPerHour, duration: duration)], lastReconciliation: Date.now, completion: { _ in })
                            }
                            
                            self.log.default("%{public}@: Succesfully started 15 min temp basal", #function)
                            completion(nil)
                        } else if duration == 1800 {
                            // 30 min. Only temp basal below 100% allowed here
                            let percentage = self.absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            guard let percentage = percentage else {
                                self.disconnect()
                                self.log.error("%{public}@: Basal schedule is not available... (30 min)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Basal schedule is not available... (30 min)")))
                                return
                            }
                            
                            let packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage, duration: .min30))
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            self.disconnect()
                            
                            guard result.success else {
                                self.log.error("%{public}@: Pump rejected command (30 min)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump rejected command (30 min)")))
                                return
                            }
                            
                            let dose = DoseEntry.tempBasal(absoluteUnit: unitsPerHour, duration: duration, insulinType: self.state.insulinType!)
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = duration
                            self.notifyStateDidChange()
                            
                            self.pumpDelegate.notify { (delegate) in
                                delegate?.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.tempBasal(dose: dose, units: unitsPerHour, duration: duration)], lastReconciliation: Date.now, completion: { _ in })
                            }
                            
                            self.log.default("%{public}@: Succesfully started 30 min temp basal", #function)
                            completion(nil)
                        } else if Int(duration) % 3600 == 0 {
                            // Only full hours are allowed here
                            let percentage = self.absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            guard let percentage = percentage else {
                                self.disconnect()
                                self.log.error("%{public}@: Basal schedule is not available... (full hour)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Basal schedule is not available... (full hour)")))
                                return
                            }
                            guard percentage < UInt8.max else {
                                self.disconnect()
                                self.log.error("%{public}@: Percentage exceeds 255%... (full hour)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Percentage exceeds 255%... (full hour)")))
                                return
                            }
                            
                            let packet = generatePacketBasalSetTemporary(options: PacketBasalSetTemporary(temporaryBasalRatio: UInt8(percentage), temporaryBasalDuration: UInt8(floor(duration / 3600))))
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            self.disconnect()
                            
                            guard result.success else {
                                self.log.error("%{public}@: Pump rejected command (full hour)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump rejected command (full hour)")))
                                return
                            }
                            
                            let dose = DoseEntry.tempBasal(absoluteUnit: unitsPerHour, duration: duration, insulinType: self.state.insulinType!)
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = duration
                            self.notifyStateDidChange()
                            
                            self.pumpDelegate.notify { (delegate) in
                                delegate?.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.tempBasal(dose: dose, units: unitsPerHour, duration: duration)], lastReconciliation: Date.now, completion: { _ in })
                            }
                            
                            self.log.default("%{public}@: Succesfully started full hourly temp basal", #function)
                            completion(nil)
                        } else {
                            // We got an unsupported duration...
                            // We will round it down to the nearest supported duration (15min, 30min, or full hour) and report the new duration back to Loop
                            
                            let percentage = self.absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            guard let percentage = percentage else {
                                self.disconnect()
                                self.log.error("%{public}@: Basal schedule is not available... (floor duration)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Basal schedule is not available... (floor duration)")))
                                return
                            }
                            
                            let newDuration: TimeInterval
                            let packet: DanaGeneratePacket
                            if duration > 3600 {
                                guard percentage < UInt8.max else {
                                    self.disconnect()
                                    self.log.error("%{public}@: Percentage exceeds 255%... (floor duration)", #function)
                                    completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Percentage exceeds 255%... (floor duration)")))
                                    return
                                }
                                
                                // Round down to nearest full hour
                                newDuration = 3600 * floor(duration / 3600)
                                packet = generatePacketBasalSetTemporary(options: PacketBasalSetTemporary(temporaryBasalRatio: UInt8(percentage), temporaryBasalDuration: UInt8(floor(duration / 3600))))
                                
                            } else if duration > 1800 {
                                // Round down to 30 min
                                newDuration = 1800
                                packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage, duration: .min30))
                                
                            } else if duration > 900 {
                                // Round down to 15 min
                                newDuration = 900
                                packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage, duration: .min15))
                                
                            } else {
                                self.disconnect()
                                self.log.error("%{public}@: Temp basal below 15 min is unsupported (floor duration)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Temp basal below 15 min is unsupported... (floor duration)")))
                                return
                            }
                            
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            self.disconnect()
                            
                            guard result.success else {
                                self.log.error("%{public}@: Pump rejected command (full hour)", #function)
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump rejected command (full hour)")))
                                return
                            }
                            
                            let dose = DoseEntry.tempBasal(absoluteUnit: unitsPerHour, duration: newDuration, insulinType: self.state.insulinType!)
                            self.state.basalDeliveryOrdinal = .tempBasal
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = unitsPerHour
                            self.state.tempBasalDuration = newDuration
                            self.notifyStateDidChange()
                            
                            self.pumpDelegate.notify { (delegate) in
                                delegate?.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.tempBasal(dose: dose, units: unitsPerHour, duration: duration)], lastReconciliation: Date.now, completion: { _ in })
                            }
                            
                            self.log.default("%{public}@: Succesfully started full hourly temp basal", #function)
                            completion(nil)
                        }
                    } catch {
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to set temp basal. Error: %{public}@", #function, error.localizedDescription)
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                }
            }
        }
    }
    
    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        log.default("%{public}@: Suspend delivery", #function)
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    do {
                        let packet = generatePacketBasalSetSuspendOn()
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        
                        guard result.success else {
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedSuspensionAdjustment))
                            return
                        }
                        
                        self.state.basalDeliveryOrdinal = .suspended
                        self.state.basalDeliveryDate = Date.now
                        self.notifyStateDidChange()
                        
                        let dose = DoseEntry.suspend()
                        self.pumpDelegate.notify { (delegate) in
                            guard let delegate = delegate else {
                                preconditionFailure("pumpManagerDelegate cannot be nil")
                            }
                            
                            delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.suspend(dose: dose)], lastReconciliation: Date.now, completion: { (error) in
                                completion(nil)
                            })
                        }
                    } catch {
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to suspend delivery. Error: %{public}@", #function, error.localizedDescription)
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                }
            }
        }
    }
    
    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        log.default("%{public}@: Resume delivery", #function)

        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    do {
                        let packet = generatePacketBasalSetSuspendOff()
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        
                        guard result.success else {
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedSuspensionAdjustment))
                            return
                        }
                        
                        self.state.basalDeliveryOrdinal = .active
                        self.state.basalDeliveryDate = Date.now
                        self.notifyStateDidChange()
                        
                        let dose = DoseEntry.resume(insulinType: self.state.insulinType!)
                        self.pumpDelegate.notify { (delegate) in
                            guard let delegate = delegate else {
                                preconditionFailure("pumpManagerDelegate cannot be nil")
                            }
                            
                            delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.resume(dose: dose)], lastReconciliation: Date.now, completion: { (error) in
                                completion(nil)
                            })
                        }
                    } catch {
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to suspend delivery. Error: %{public}@", #function, error.localizedDescription)
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                }
            }
        }
    }
    
    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        log.default("%{public}@: Sync basal", #function)

        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                completion(.failure(PumpManagerError.connection(DanaKitPumpManagerError.noConnection)))
                return
            case .success:
                Task {
                    do {
                        let basal = DanaKitPumpManagerState.convertBasal(scheduleItems)
                        let packet = try generatePacketBasalSetProfileRate(options: PacketBasalSetProfileRate(profileNumber: self.basalProfileNumber, profileBasalRate: basal))
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        guard result.success else {
                            self.disconnect()
                            completion(.failure(PumpManagerError.configuration(DanaKitPumpManagerError.failedBasalAdjustment)))
                            return
                        }
                        
                        let activatePacket = generatePacketBasalSetProfileNumber(options: PacketBasalSetProfileNumber(profileNumber: self.basalProfileNumber))
                        let activateResult = try await DanaKitPumpManager.bluetoothManager.writeMessage(activatePacket)
                        
                        self.disconnect()
                        
                        guard activateResult.success else {
                            completion(.failure(PumpManagerError.configuration(DanaKitPumpManagerError.failedBasalAdjustment)))
                            return
                        }
                        
                        guard let schedule = DailyValueSchedule<Double>(dailyItems: scheduleItems) else {
                            completion(.failure(PumpManagerError.configuration(DanaKitPumpManagerError.failedBasalGeneration)))
                            return
                        }
                        
                        self.currentBaseBasalRate = schedule.value(at: Date.now)
                        self.state.basalDeliveryOrdinal = .active
                        self.state.basalDeliveryDate = Date.now
                        self.state.basalSchedule = basal
                        self.notifyStateDidChange()
                        
                        let dose = DoseEntry.basal(rate: self.currentBaseBasalRate, insulinType: self.state.insulinType!)
                        self.pumpDelegate.notify { (delegate) in
                            guard let delegate = delegate else {
                                preconditionFailure("pumpManagerDelegate cannot be nil")
                            }
                            
                            delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)], lastReconciliation: Date.now, completion: { (error) in
                                completion(.success(schedule))
                            })
                        }
                    } catch {
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to suspend delivery. Error: %{public}@", #function, error.localizedDescription)
                        completion(.failure(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription))))
                    }
                }
            }
        }
    }
    
    public func setUserSettings(data: PacketGeneralSetUserOption, completion: @escaping (Bool) -> Void) {
        log.default("%{public}@: Set user settings", #function)
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                completion(false)
                return
            case .success:
                Task {
                    do {
                        let packet = generatePacketGeneralSetUserOption(options: data)
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        completion(result.success)
                    } catch {
                        self.log.error("%{public}@: error caught %{public}@", #function, error.localizedDescription)
                        self.disconnect()
                        completion(false)
                    }
                }
            }
        }
    }
    
    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        // Dana does not allow the max basal and max bolus to be set
        // Max basal = 3 U/hr
        // Max bolus = 20U
        
        completion(.success(deliveryLimits))
    }
    
    public func syncPumpTime(completion: @escaping (Error?) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpIsBusy))
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                self.log.error("%{public}@: Connection error", #function)
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    do {
                        let offset = Date.now.timeIntervalSince(self.state.pumpTime ?? Date.distantPast)
                        let packet = generatePacketGeneralSetPumpTimeUtcWithTimezone(options: PacketGeneralSetPumpTimeUtcWithTimezone(time: Date.now, zoneOffset: UInt8(round(Double(TimeZone.current.secondsFromGMT(for: Date.now) / 3600)))))
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        
                        guard result.success else {
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTimeAdjustment))
                            return
                        }
                        
                        self.pumpDelegate.notify { (delegate) in
                            delegate?.pumpManager(self, didAdjustPumpClockBy: offset)
                        }
                        completion(nil)
                    } catch {
                        self.disconnect()
                        self.log.error("%{public}@: Failed to sync time. Error: %{public}@", #function, error.localizedDescription)
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.unknown(error.localizedDescription)))
                    }
                }
            }
        }
    }
    
    private func device() -> HKDevice {
        return HKDevice(
            name: managerIdentifier,
            manufacturer: "Sooil",
            model: self.state.getFriendlyDeviceName(),
            hardwareVersion: String(self.state.hwModel),
            firmwareVersion: String(self.state.pumpProtocol),
            softwareVersion: "",
            localIdentifier: self.state.deviceName,
            udiDeviceIdentifier: nil
        )
    }
    
    private func ensureConnected(_ completion: @escaping (ConnectionResult) -> Void) {
        // Device still has an active connection with pump and is probably busy with something
        if DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral?.state == .connected {
            completion(.failure)
            
        // State hasnt been updated yet, so we have to try to connect
        } else if DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral != nil {
            self.connect(DanaKitPumpManager.bluetoothManager.peripheral!) { error in
                if error == nil {
                    completion(.success)
                } else {
                    completion(.failure)
                }
            }
        
        // There is no active connection, but we stored the peripheral. We can quickly reconnect
        } else if !DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral != nil {
            self.connect(DanaKitPumpManager.bluetoothManager.peripheral!) { error in
                if error == nil {
                    completion(.success)
                } else {
                    completion(.failure)
                }
            }
            
        // No active connection and no stored peripheral. We have to scan for device before being able to send command
        } else if !DanaKitPumpManager.bluetoothManager.isConnected && self.state.bleIdentifier != nil {
            do {
                try DanaKitPumpManager.bluetoothManager.connect(self.state.bleIdentifier!) { error in
                    if error == nil {
                        completion(.success)
                    } else {
                        completion(.failure)
                    }
                }
            } catch {
                completion(.failure)
            }
        
        // Should never reach, but is only possible if device is not onboard (we have no ble identifier to connect to)
        } else {
            log.error("%{public}@: Pump is not onboarded", #function)
            completion(.failure)
        }
    }
    
    private func disconnect() {
        if DanaKitPumpManager.bluetoothManager.isConnected {
            DanaKitPumpManager.bluetoothManager.disconnect(DanaKitPumpManager.bluetoothManager.peripheral!)
        }
    }
    
    private func absoluteBasalRateToPercentage(absoluteValue: Double, basalSchedule: [Double]) -> UInt16? {
        guard basalSchedule.count > 0 else {
            return nil
        }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let nowTimeInterval = now.timeIntervalSince(startOfDay)
        
        let basalIntervals: [TimeInterval] = Array(0..<24).map({ TimeInterval(60 * 60 * $0) })
        let basalIndex = basalIntervals.firstIndex(where: { $0 > nowTimeInterval})! - 1
        let basalRate = basalSchedule[basalIndex]
        
        return UInt16(round(absoluteValue / basalRate * 100))
    }
}

extension DanaKitPumpManager: AlertSoundVendor {
    public func getSoundBaseURL() -> URL? {
        return nil
    }

    public func getSounds() -> [LoopKit.Alert.Sound] {
        return []
    }
}

extension DanaKitPumpManager {
    public func acknowledgeAlert(alertIdentifier: LoopKit.Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
    }
}

// MARK: State observers
extension DanaKitPumpManager {
    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        statusObservers.insert(observer, queue: queue)
    }
    
    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        statusObservers.removeElement(observer)
    }
    
    public func addStateObserver(_ observer: StateObserver, queue: DispatchQueue) {
        stateObservers.insert(observer, queue: queue)
    }

    public func removeStateObserver(_ observer: StateObserver) {
        stateObservers.removeElement(observer)
    }
    
    public func notifyStateDidChange() {
        DispatchQueue.main.async {
            self.stateObservers.forEach { (observer) in
                observer.stateDidUpdate(self.state, self.oldState)
            }
            
            self.pumpDelegate.notify { (delegate) in
                delegate?.pumpManagerDidUpdateState(self)
            }
            
            self.statusObservers.forEach { (observer) in
                observer.pumpManager(self, didUpdate: self.status(self.state), oldStatus: self.status(self.oldState))
            }
            
            self.oldState = DanaKitPumpManagerState(rawValue: self.state.rawValue)
        }
    }
    
    public func addScanDeviceObserver(_ observer: StateObserver, queue: DispatchQueue) {
        scanDeviceObservers.insert(observer, queue: queue)
    }

    public func removeScanDeviceObserver(_ observer: StateObserver) {
        scanDeviceObservers.removeElement(observer)
    }
    
    func notifyAlert(_ alert: PumpManagerAlert) {
        let identifier = Alert.Identifier(managerIdentifier: self.managerIdentifier, alertIdentifier: alert.identifier)
        let loopAlert = Alert(identifier: identifier, foregroundContent: alert.foregroundContent, backgroundContent: alert.backgroundContent, trigger: .immediate)
        
        let event = NewPumpEvent(date: Date(), dose: nil, raw: alert.raw, title: "Alarm: \(alert.foregroundContent.title)", type: .alarm, alarmType: alert.type)
        
        self.pumpDelegate.notify { delegate in
            delegate?.issueAlert(loopAlert)
            delegate?.pumpManager(self, hasNewPumpEvents: [event], lastReconciliation: Date(), completion: { _ in })
        }
    }
    
    func notifyScanDeviceDidChange(_ device: DanaPumpScan) {
        DispatchQueue.main.async {
            self.scanDeviceObservers.forEach { (observer) in
                observer.deviceScanDidUpdate(device)
            }
        }
    }
    
    func notifyBolusError() {
        guard let doseEntry = self.doseEntry, self.state.bolusState != .noBolus else {
            // Ignore if no bolus is going
            return
        }
        
        self.state.bolusState = .noBolus
        self.notifyStateDidChange()
        
        let dose = doseEntry.toDoseEntry()
        let deliveredUnits = doseEntry.deliveredUnits
        
        self.doseEntry = nil
        self.doseReporter = nil
        
        guard let dose = dose else {
            return
        }
        
        DispatchQueue.main.async {
            self.pumpDelegate.notify { (delegate) in
                guard let delegate = delegate else {
                    preconditionFailure("pumpManagerDelegate cannot be nil")
                }
                
                delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: deliveredUnits)], lastReconciliation: Date.now, completion: { _ in })
            }
        }
    }
    
    func notifyBolusDidUpdate(deliveredUnits: Double) {
        guard let doseEntry = self.doseEntry else {
            return
        }
        
        doseEntry.deliveredUnits = deliveredUnits
        self.doseReporter?.notify(deliveredUnits: deliveredUnits)
    }
    
    func notifyBolusDone(deliveredUnits: Double) {
        self.state.bolusState = .noBolus
        self.notifyStateDidChange()
        self.disconnect()
        
        guard let doseEntry = self.doseEntry else {
            return
        }
        
        doseEntry.deliveredUnits = deliveredUnits
        
        let dose = doseEntry.toDoseEntry()
        self.doseEntry = nil
        self.doseReporter = nil
        
        guard let dose = dose else {
            return
        }
        
        DispatchQueue.main.async {
            self.pumpDelegate.notify { (delegate) in
                guard let delegate = delegate else {
                    preconditionFailure("pumpManagerDelegate cannot be nil")
                }
                
                delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: deliveredUnits)], lastReconciliation: Date.now, completion: { _ in })
            }
            
            self.notifyStateDidChange()
        }
    }
}
