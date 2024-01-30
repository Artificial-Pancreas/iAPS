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
import SwiftUI
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
    
    public func connect(_ peripheral: CBPeripheral, _ view: UIViewController?, _ completion: @escaping (Error?) -> Void) {
        DanaKitPumpManager.bluetoothManager.connect(peripheral, view, completion)
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
            pumpBatteryChargeRemaining: state.batteryRemaining,
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
        guard self.state.bolusState == .noBolus else {
            completion?(nil)
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                completion?(nil)
                return
            case .success:
                Task {
                    let events = await self.syncHistory()
                    self.state.lastStatusDate = Date()
                    
                    self.disconnect()
 
                    DispatchQueue.main.async {
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
    
    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
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
        guard self.state.bolusState == .noBolus else {
            completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpIsBusy))
            return
        }
        
        self.state.bolusState = .initiating
        self.notifyStateDidChange()
        
        self.ensureConnected { result in
            switch result {
            case .failure:
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
                        
                        self.doseEntry = UnfinalizedDose(units: units, duration: self.estimatedDuration(toBolus: units), activationType: activationType, insulinType: self.state.insulinType!)
                        self.doseReporter = DanaKitDoseProgressReporter(total: units)
                        
                        self.state.lastStatusDate = Date()
                        self.state.bolusState = .inProgress
                        self.notifyStateDidChange()
                        
                        completion(nil)
                    } catch {
                        self.state.bolusState = .noBolus
                        self.notifyStateDidChange()
                        self.disconnect()
                        
                        self.log.error("%{public}@: Failed to do bolus. Error: %{public}@", #function, error.localizedDescription)
                        completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                    }
                }
            }
        }
    }
    
    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        let oldBolusState = self.state.bolusState
        self.state.bolusState = .canceling
        self.notifyStateDidChange()
        
        self.ensureConnected { result in
            switch result {
            case .failure:
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
                        
                        completion(.failure(PumpManagerError.communication(DanaKitPumpManagerError.noConnection)))
                    }
                }
            }
        }
    }
    
    /// NOTE: There are 2 ways to set a temp basal:
    /// - The normal way (which only accepts full hours and percentages)
    /// - A short APS-special temp basal command (which only accepts 15 min (only above 100%) or 30 min (only below 100%)
    /// Currently, the above is implemented with a simpel U/hr -> % calculator
    /// TODO: Finetune the calculator and find a way to deal with 90 min temp basal i.e.
    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval, completion: @escaping (PumpManagerError?) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpIsBusy))
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    guard !self.state.isPumpSuspended else {
                        self.disconnect()
                        completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpSuspended))
                        return
                    }
                    
                    do {
                        if (duration < .ulpOfOne) {
                            let packet = generatePacketBasalCancelTemporary()
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            
                            self.disconnect()
                            
                            guard result.success else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump send error")))
                                return
                            }
                            
                            self.state.basalDeliveryOrdinal = .active
                            self.state.basalDeliveryDate = Date.now
                            self.state.tempBasalUnits = nil
                            self.state.tempBasalDuration = nil
                            self.notifyStateDidChange()
                            
                            let dose = DoseEntry.basal(rate: self.currentBaseBasalRate, insulinType: self.state.insulinType!)
                            self.pumpDelegate.notify { (delegate) in
                                delegate?.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)], lastReconciliation: Date.now, completion: { _ in })
                            }
                            
                            completion(nil)
                            
                        } else if duration == 900 {
                            // 15 min. Only basal boosts allowed here
                            let percentage = absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            guard percentage > 100 else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Temp basal is above or equal to 100%")))
                                return
                            }
                            
                            let packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage))
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            
                            guard result.success else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump send error")))
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
                        } else if duration == 1800 {
                            // 30 min. Only temp basal below 100% allowed here
                            let percentage = absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            guard percentage < 100 else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Temp basal is below or equal to 100%")))
                                return
                            }
                            
                            let packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage))
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            
                            guard result.success else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump send error")))
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
                        } else if Int(duration) % 60 == 0 {
                            // Only full hours are allowed here
                            let percentage = absoluteBasalRateToPercentage(absoluteValue: unitsPerHour, basalSchedule: self.state.basalSchedule)
                            let packet = generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal(percent: percentage))
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            
                            guard result.success else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment("Pump send error")))
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
                        } else {
                            self.disconnect()
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.unsupportedTempBasal(duration)))
                        }
                    } catch {
                        self.disconnect()
                        completion(PumpManagerError.communication(nil))
                    }
                }
            }
        }
    }
    
    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpIsBusy))
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
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
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.noConnection))
                    }
                }
            }
        }
    }
    
    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpIsBusy))
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
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
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.noConnection))
                    }
                }
            }
        }
    }
    
    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>], completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(.failure(PumpManagerError.deviceState(DanaKitPumpManagerError.pumpIsBusy)))
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                completion(.failure(PumpManagerError.connection(DanaKitPumpManagerError.noConnection)))
                return
            case .success:
                Task {
                    do {
                        let basal = self.convertBasal(scheduleItems)
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
                        completion(.failure(PumpManagerError.communication(DanaKitPumpManagerError.noConnection)))
                    }
                }
            }
        }
    }
    
    public func getUserSettings(completion: @escaping (PacketGeneralGetUserOption?) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(nil)
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
                completion(nil)
                return
            case .success:
                Task {
                    do {
                        let packet = generatePacketGeneralGetUserOption()
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        
                        guard result.success else {
                            completion(nil)
                            return
                        }
                        
                        completion(result.data as? PacketGeneralGetUserOption)
                    } catch {
                        self.disconnect()
                        completion(nil)
                    }
                }
            }
        }
    }
    
    public func setUserSettings(data: PacketGeneralSetUserOption, completion: @escaping (Bool) -> Void) {
        guard self.state.bolusState == .noBolus else {
            completion(false)
            return
        }
        
        self.ensureConnected { result in
            switch result {
            case .failure:
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
                completion(PumpManagerError.connection(DanaKitPumpManagerError.noConnection))
                return
            case .success:
                Task {
                    do {
                        let packet = generatePacketGeneralSetPumpTimeUtcWithTimezone(options: PacketGeneralSetPumpTimeUtcWithTimezone(time: Date.now, zoneOffset: UInt8(round(Double(TimeZone.current.secondsFromGMT(for: Date.now) / 3600)))))
                        let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                        
                        self.disconnect()
                        
                        guard result.success else {
                            completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTimeAdjustment))
                            return
                        }
                        
                        completion(nil)
                    } catch {
                        self.disconnect()
                        completion(PumpManagerError.communication(DanaKitPumpManagerError.noConnection))
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
    
    private func convertBasal(_ scheduleItems: [RepeatingScheduleValue<Double>]) -> [Double] {
        let basalIntervals: [TimeInterval] = Array(0..<24).map({ TimeInterval(60 * 60 * $0) })
        var output: [Double] = []
        
        var currentIndex = 0
        for i in 0..<24 {
            if (currentIndex >= scheduleItems.count) {
                output.append(scheduleItems[currentIndex - 1].value)
            } else if (scheduleItems[currentIndex].startTime != basalIntervals[i]) {
                output.append(scheduleItems[currentIndex - 1].value)
            } else {
                output.append(scheduleItems[currentIndex].value)
                currentIndex += 1
            }
        }
        
        return output
    }
    
    private func ensureConnected(_ completion: @escaping (ConnectionResult) -> Void) {
        // Device still has an active connection with pump and is probably busy with something
        if DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral?.state == .connected {
            completion(.failure)
            
        // State hasnt been updated yet, so we have to try to connect
        } else if DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral != nil {
            self.connect(DanaKitPumpManager.bluetoothManager.peripheral!, nil, { error in
                if error == nil {
                    completion(.success)
                } else {
                    completion(.failure)
                }
            })
        
        // There is no active connection, but we stored the peripheral. We can quickly reconnect
        } else if !DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral != nil {
            self.connect(DanaKitPumpManager.bluetoothManager.peripheral!, nil, { error in
                if error == nil {
                    completion(.success)
                } else {
                    completion(.failure)
                }
            })
            
        // No active connection and no stored peripheral. We have to scan for device before being able to send command
        } else if !DanaKitPumpManager.bluetoothManager.isConnected && self.state.bleIdentifier != nil {
            do {
                try DanaKitPumpManager.bluetoothManager.connect(self.state.bleIdentifier!, nil, { error in
                    if error == nil {
                        completion(.success)
                    } else {
                        completion(.failure)
                    }
                })
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
