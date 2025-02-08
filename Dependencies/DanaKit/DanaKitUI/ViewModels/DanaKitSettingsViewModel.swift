//
//  DanaKitSettingsViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 03/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

class DanaKitSettingsViewModel : ObservableObject {
    @Published var showingDeleteConfirmation = false
    @Published var showingBleModeSwitch = false
    @Published var showingTimeSyncConfirmation = false
    @Published var showingDisconnectReminder = false
    @Published var showingBolusSyncingDisabled = false
    @Published var showingBlindReservoirCannulaRefill = false
    @Published var basalButtonText: String = ""
    @Published var bolusSpeed: BolusSpeed
    @Published var isUsingContinuousMode: Bool = false
    @Published var isUpdatingPumpState: Bool = false
    @Published var isConnected: Bool = false
    @Published var isTogglingConnection: Bool = false
    @Published var isBolusSyncingDisabled = false
    @Published var isSyncing: Bool = false
    @Published var lastSync: Date? = nil
    @Published var batteryLevel: Double = 0
    @Published var showingSilentTone: Bool = false
    @Published var silentTone: Bool = false
    @Published var basalProfileNumber: UInt8 = 0
    @Published var cannulaAge: String? = nil
    @Published var reservoirAge: String? = nil
    @Published var batteryAge: String? = nil
    
    @Published var showPumpTimeSyncWarning: Bool = false
    @Published var pumpTime: Date? = nil
    @Published var pumpTimeSyncedAt: Date? = nil
    @Published var nightlyPumpTimeSync: Bool = false
    
    @Published var reservoirLevelWarning: Double
    @Published var reservoirLevel: Double?
    @Published var isSuspended: Bool = false
    @Published var basalRate: Double?
    @Published var showingReservoirCannulaRefillView: Bool = false
    
    private let log = DanaLogger(category: "SettingsView")
    private(set) var insulinType: InsulinType
    private(set) var pumpManager: DanaKitPumpManager?
    private var didFinish: (() -> Void)?
    private(set) var userOptionsView: DanaKitUserSettingsView
    private(set) var refillView: DanaKitRefillReservoirAndCannulaView

    public var pumpModel: String {
        self.pumpManager?.state.getFriendlyDeviceName() ?? ""
    }

    public var deviceName: String? {
        self.pumpManager?.state.deviceName
    }
    
    public var hardwareModel: UInt8? {
        self.pumpManager?.state.hwModel
    }
    
    public var firmwareVersion: UInt8? {
        self.pumpManager?.state.pumpProtocol
    }
    
    public var isTempBasal: Bool {
        guard let pumpManager = self.pumpManager else {
            return false
        }
        
        return pumpManager.state.basalDeliveryOrdinal == .tempBasal && pumpManager.state.tempBasalEndsAt > Date.now
    }

    
    let basalRateFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 1
        numberFormatter.minimumIntegerDigits = 1
        return numberFormatter
    }()
    
    let reservoirVolumeFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit())
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter
    }()
    
    private let dateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
    
    public init(_ pumpManager: DanaKitPumpManager?, _ didFinish: (() -> Void)?) {
        self.pumpManager = pumpManager
        self.didFinish = didFinish
        
        self.userOptionsView = DanaKitUserSettingsView(viewModel: DanaKitUserSettingsViewModel(self.pumpManager))
        self.refillView = DanaKitRefillReservoirAndCannulaView(viewModel: DanaKitRefillReservoirCannulaViewModel(pumpManager: pumpManager, cannulaOnly: false))
        
        self.isUsingContinuousMode = self.pumpManager?.state.isUsingContinuousMode ?? false
        self.isConnected = self.pumpManager?.state.isConnected ?? false
        self.insulinType = self.pumpManager?.state.insulinType ?? .novolog
        self.bolusSpeed = self.pumpManager?.state.bolusSpeed ?? .speed12
        self.lastSync = self.pumpManager?.state.lastStatusDate
        self.reservoirLevel = self.pumpManager?.state.reservoirLevel
        self.isSuspended = self.pumpManager?.state.isPumpSuspended ?? false
        self.pumpTime = self.pumpManager?.state.pumpTime
        self.pumpTimeSyncedAt = self.pumpManager?.state.pumpTimeSyncedAt
        self.nightlyPumpTimeSync = self.pumpManager?.state.allowAutomaticTimeSync ?? false
        self.isBolusSyncingDisabled = self.pumpManager?.state.isBolusSyncDisabled ?? false
        self.batteryLevel = self.pumpManager?.state.batteryRemaining ?? 0
        self.silentTone = self.pumpManager?.state.useSilentTones ?? false
        self.reservoirLevelWarning = Double(self.pumpManager?.state.lowReservoirRate ?? 20)
        self.basalProfileNumber = self.pumpManager?.state.basalProfileNumber ?? 0
        self.showPumpTimeSyncWarning = self.pumpManager?.state.shouldShowTimeWarning() ?? false
        updateBasalRate()
        
        if let cannulaDate = self.pumpManager?.state.cannulaDate {
            self.cannulaAge = formatDateToDayHour(cannulaDate)
        }
        
        if let reservoirDate = self.pumpManager?.state.reservoirDate {
            self.reservoirAge = formatDateToDayHour(reservoirDate)
        }
        
        if let batteryDate = self.pumpManager?.state.batteryAge {
            self.batteryAge = formatDateToDayHour(batteryDate)
        }
        
        self.basalButtonText = self.updateBasalButtonText()
        
        self.pumpManager?.addStateObserver(self, queue: .main)
    }
    
    func stopUsingDana() {
        self.pumpManager?.notifyDelegateOfDeactivation {
            DispatchQueue.main.async {
                self.didFinish?()
            }
        }
    }
    
    func updateReservoirAge() {
        self.pumpManager?.state.reservoirDate = Date.now
        self.reservoirAge = formatDateToDayHour(Date.now)
        self.pumpManager?.notifyStateDidChange()
    }
    
    func updateCannulaAge() {
        self.pumpManager?.state.cannulaDate = Date.now
        self.cannulaAge = formatDateToDayHour(Date.now)
        self.pumpManager?.notifyStateDidChange()
    }
    
    func updateBatteryAge() {
        self.pumpManager?.state.batteryAge = Date.now
        self.batteryAge = formatDateToDayHour(Date.now)
        self.pumpManager?.notifyStateDidChange()
    }
    
    func scheduleDisconnectNotification(_ duration: TimeInterval) {
        NotificationHelper.setDisconnectReminder(duration)
        self.pumpManager?.disconnect(true)
    }
    
    func navigateToRefillView(_ cannulaOnly: Bool) {
        self.refillView = DanaKitRefillReservoirAndCannulaView(viewModel: DanaKitRefillReservoirCannulaViewModel(pumpManager: pumpManager, cannulaOnly: cannulaOnly))
        self.showingReservoirCannulaRefillView = true
    }
    
    func forceDisconnect() {
        self.pumpManager?.disconnect(true)
    }
    
    func didChangeInsulinType(_ newType: InsulinType?) {
        guard let type = newType else {
            return
        }
        
        self.pumpManager?.state.insulinType = type
        self.pumpManager?.notifyStateDidChange()
        self.insulinType = type
    }
    
    func getLogs() -> [URL] {
        if let pumpManager = self.pumpManager {
            log.info(pumpManager.state.debugDescription)
        }
        return log.getDebugLogs()
    }
    
    func toggleBleMode() {
        self.pumpManager?.toggleBluetoothMode()
        self.isTogglingConnection = true;
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.isTogglingConnection = false;
        }
    }
    
    func reconnect() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.isTogglingConnection = true
        pumpManager.reconnect { _ in
            DispatchQueue.main.async {
                self.isTogglingConnection = false
            }
        }
    }
    
    func formatDate(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        return self.dateFormatter.string(from: date)
    }
    
    func didBolusSpeedChanged(_ bolusSpeed: BolusSpeed) {
        self.pumpManager?.state.bolusSpeed = bolusSpeed
        self.pumpManager?.notifyStateDidChange()
        self.bolusSpeed = bolusSpeed
    }
    
    func syncData() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        DispatchQueue.main.async {
            self.isSyncing = true
        }
        
        pumpManager.syncPump { date in
            DispatchQueue.main.async {
                self.isSyncing = false
                
                if let date = date {
                    self.lastSync = date
                }
            }
        }
    }
    
    func updateNightlyPumpTimeSync(_ value: Bool) {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        pumpManager.state.allowAutomaticTimeSync = value
        pumpManager.notifyStateDidChange()
    }
    
    func syncPumpTime() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.isSyncing = true
        pumpManager.syncPumpTime(completion: { error in
            self.syncData()
        })
    }
    
    func reservoirText(for units: Double) -> String {
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: units)
        return reservoirVolumeFormatter.string(from: quantity, for: .internationalUnit()) ?? ""
    }
    
    func toggleSilentTone() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        pumpManager.state.useSilentTones = !self.silentTone
        self.silentTone = pumpManager.state.useSilentTones
    }
    
    func toggleBolusSyncing() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        pumpManager.state.isBolusSyncDisabled = !self.isBolusSyncingDisabled
        pumpManager.notifyStateDidChange()
    }
    
    func transformBasalProfile(_ index: UInt8) -> String {
        if index == 0 {
            return "A"
        } else if index == 1 {
            return "B"
        } else if index == 2 {
            return "C"
        } else {
            return "D"
        }
    }
    
    func suspendResumeButtonPressed() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.isUpdatingPumpState = true
        
        if pumpManager.state.isPumpSuspended {
            self.pumpManager?.resumeDelivery{ error in
                DispatchQueue.main.async {
                    self.basalButtonText = self.updateBasalButtonText()
                    self.isUpdatingPumpState = false
                }
                
                // Check if action failed, otherwise skip state sync
                guard error == nil else {
                    self.log.error("\(#function): failed to resume delivery. Error: \(error!.localizedDescription)")
                    return
                }
            }
            
            return
        }
        
        if isTempBasal {
            // Stop temp basal
            self.pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0, completion: { error in
                DispatchQueue.main.async {
                    self.basalButtonText = self.updateBasalButtonText()
                    self.isUpdatingPumpState = false
                }
                
                // Check if action failed, otherwise skip state sync
                guard error == nil else {
                    self.log.error("\(#function): failed to stop temp basal. Error: \(error!.localizedDescription)")
                    return
                }
            })
            
            return
        }
        
        pumpManager.suspendDelivery(completion: { error in
            DispatchQueue.main.async {
                self.basalButtonText = self.updateBasalButtonText()
                self.isUpdatingPumpState = false
            }
            
            // Check if action failed, otherwise skip state sync
            guard error == nil else {
                self.log.error("\(#function): failed to suspend delivery. Error: \(error!.localizedDescription)")
                return
            }
        })
    }
    
    private func updateBasalButtonText() -> String {
        guard let pumpManager = self.pumpManager else {
            return LocalizedString("Suspend delivery", comment: "Dana settings suspend delivery")
        }
        
        if pumpManager.state.isPumpSuspended {
            return LocalizedString("Resume delivery", comment: "Dana settings resume delivery")
        }
        
        if isTempBasal {
            return LocalizedString("Stop temp basal", comment: "Dana settings stop temp basal")
        }
        
        return LocalizedString("Suspend delivery", comment: "Dana settings suspend delivery")
    }
    
    private func updateBasalRate() {
        guard let pumpManager = self.pumpManager else {
            self.basalRate = 0
            return
        }
        
        if pumpManager.state.basalDeliveryOrdinal == .tempBasal && pumpManager.state.tempBasalEndsAt > Date.now {
            self.basalRate = pumpManager.state.tempBasalUnits ?? pumpManager.currentBaseBasalRate
        } else {
            self.basalRate = pumpManager.currentBaseBasalRate
        }
    }
    
    private func formatDateToDayHour(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: date, to: Date.now)
        if let days = components.day, let hours = components.hour {
            return "\(days)d \(hours)h"
        }
        
        return "?d ?h"
    }
}

extension DanaKitSettingsViewModel: StateObserver {
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _ oldState: DanaKitPumpManagerState) {
        self.isUsingContinuousMode = state.isUsingContinuousMode
        self.isConnected = state.isConnected
        self.insulinType = state.insulinType ?? .novolog
        self.bolusSpeed = state.bolusSpeed
        self.lastSync = state.lastStatusDate
        self.reservoirLevel = state.reservoirLevel
        self.isSuspended = state.isPumpSuspended
        self.isBolusSyncingDisabled = state.isBolusSyncDisabled
        self.pumpTime = state.pumpTime
        self.pumpTimeSyncedAt = state.pumpTimeSyncedAt
        self.nightlyPumpTimeSync = state.allowAutomaticTimeSync
        self.batteryLevel = state.batteryRemaining
        self.silentTone = state.useSilentTones
        self.basalProfileNumber = state.basalProfileNumber
        self.showPumpTimeSyncWarning = state.shouldShowTimeWarning()
        updateBasalRate()
        
        self.basalButtonText = self.updateBasalButtonText()
        
        if let cannulaDate = state.cannulaDate {
            self.cannulaAge = formatDateToDayHour(cannulaDate)
        }
        
        if let reservoirDate = state.reservoirDate {
            self.reservoirAge = formatDateToDayHour(reservoirDate)
        }
        
        if let batteryAge = state.batteryAge {
            self.batteryAge = formatDateToDayHour(batteryAge)
        }
    }
    
    func deviceScanDidUpdate(_ device: DanaPumpScan) {
        // Don't do anything here. We are not scanning for a new pump
    }
}
