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
                // TODO: Sync pump history
                
                self.state.lastStatusDate = Date()
                
                // By connecting to the pump, the state gets updated
                self.disconnect()
                
                self.pumpDelegate.notify { (delegate) in
                    guard let delegate = delegate else {
                        preconditionFailure("pumpManagerDelegate cannot be nil")
                    }

                    delegate.pumpManager(self, hasNewPumpEvents: [], lastReconciliation: Date.now, completion: { (error) in
                        completion?(Date.now)
                    })
                }
            }
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
    /// TODO: Need to discuss what to do here / how to make this work within the Loop algorithm AND if the convertion from absolute to percentage is acceptable
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
                    
                    if (duration < .ulpOfOne) {
                        do {
                            let packet = generatePacketBasalCancelTemporary()
                            let result = try await DanaKitPumpManager.bluetoothManager.writeMessage(packet)
                            
                            self.disconnect()
                            
                            guard result.success else {
                                completion(PumpManagerError.configuration(DanaKitPumpManagerError.failedTempBasalAdjustment))
                                return
                            }
                            
                            self.state.basalDeliveryOrdinal = .active
                            self.state.basalDeliveryDate = Date.now
                            self.notifyStateDidChange()
                            
                            let dose = DoseEntry.basal(rate: self.currentBaseBasalRate, insulinType: self.state.insulinType!)
                            self.pumpDelegate.notify { (delegate) in
                                guard let delegate = delegate else {
                                    preconditionFailure("pumpManagerDelegate cannot be nil")
                                }
                                
                                delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.basal(dose: dose)], lastReconciliation: Date.now, completion: { (error) in
                                    completion(nil)
                                })
                            }
                        } catch {
                            self.disconnect()
                            completion(PumpManagerError.communication(nil))
                        }
                    } else {
                        self.disconnect()
                        completion(PumpManagerError.configuration(DanaKitPumpManagerError.unsupportedTempBasal))
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
    
    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits, completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        // Dana does not allow the max basal and max bolus to be set
        // Max basal = 3 U/hr
        // Max bolus = 20U
        
        completion(.success(deliveryLimits))
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
        // Device still has an active connection with pump
        if DanaKitPumpManager.bluetoothManager.isConnected && DanaKitPumpManager.bluetoothManager.peripheral?.state == .connected {
            completion(.success)
            
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
        
        self.pumpDelegate.notify { (delegate) in
            guard let delegate = delegate else {
                preconditionFailure("pumpManagerDelegate cannot be nil")
            }

            delegate.pumpManager(self, hasNewPumpEvents: [NewPumpEvent.bolus(dose: dose, units: deliveredUnits)], lastReconciliation: Date.now, completion: { _ in })
        }
    }
}
