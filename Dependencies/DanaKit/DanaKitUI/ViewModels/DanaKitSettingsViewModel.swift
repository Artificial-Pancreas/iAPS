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
    @Published var basalButtonText: String = ""
    @Published var bolusSpeed: BolusSpeed
    @Published var isSyncing: Bool = false
    @Published var lastSync: Date? = nil
    
    private(set) var insulineType: InsulinType
    private var pumpManager: DanaKitPumpManager?
    private var didFinish: (() -> Void)?
    
    private(set) var reservoirLevelWarning: Double = 20
    
    public var pumpModel: String {
        self.pumpManager?.state.getFriendlyDeviceName() ?? ""
    }
    
    public var isSuspended: Bool {
        self.pumpManager?.state.isPumpSuspended ?? true
    }
    
    public var basalRate: Double? {
        self.pumpManager?.currentBaseBasalRate
    }
    
    public var reservoirLevel: Double? {
        self.pumpManager?.state.reservoirLevel
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
        formatter.timeStyle = .long
        return formatter
    }
    
    public init(_ pumpManager: DanaKitPumpManager?, _ didFinish: (() -> Void)?) {
        self.pumpManager = pumpManager
        self.didFinish = didFinish
        
        self.insulineType = self.pumpManager?.state.insulinType ?? .novolog
        self.bolusSpeed = self.pumpManager?.state.bolusSpeed ?? .speed12
        self.lastSync = self.pumpManager?.state.lastStatusDate
        
        self.basalButtonText = self.updateBasalButtonText()
    }
    
    func stopUsingDana() {
        self.pumpManager?.notifyDelegateOfDeactivation {
            DispatchQueue.main.async {
                self.didFinish?()
            }
        }
    }
    
    func didChangeInsulinType(_ newType: InsulinType?) {
        guard let type = newType else {
            return
        }
        
        self.pumpManager?.state.insulinType = type
        self.insulineType = type
    }
    
    func formatDate(_ date: Date?) -> String {
        guard let date = date else {
            return ""
        }
        
        return self.dateFormatter().string(from: date)
    }
    
    func didBolusSpeedChanged(_ bolusSpeed: BolusSpeed) {
        self.pumpManager?.state.bolusSpeed = bolusSpeed
        self.bolusSpeed = bolusSpeed
    }
    
    func syncData() {
        guard let pumpManager = self.pumpManager else {
            return
        }
        
        self.isSyncing = true
        pumpManager.ensureCurrentPumpData(completion: { date in
            self.isSyncing = false
            self.lastSync = date
        })
    }
    
    func reservoirText(for units: Double) -> String {
        let quantity = HKQuantity(unit: .internationalUnit(), doubleValue: units)
        return reservoirVolumeFormatter.string(from: quantity, for: .internationalUnit()) ?? ""
    }
    
    func suspendResumeButtonPressed() {
        guard self.pumpManager?.state.isConnected ?? false else {
            return
        }
        
        if self.pumpManager?.state.isPumpSuspended ?? false {
            self.pumpManager?.resumeDelivery(completion: { error in
                guard error == nil else {
                    return
                }
                
                self.basalButtonText = self.updateBasalButtonText()
            })
            
            return
        }
        
        if self.pumpManager?.state.isTempBasalInProgress ?? false {
            // Stop temp basal
            self.pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0, completion: { error in
                guard error == nil else {
                    return
                }
                
                self.basalButtonText = self.updateBasalButtonText()
            })
            
            return
        }
        
        self.pumpManager?.suspendDelivery(completion: { error in
            guard error == nil else {
                return
            }
            
            self.basalButtonText = self.updateBasalButtonText()
        })
    }
    
    private func updateBasalButtonText() -> String {
        if self.pumpManager?.state.isPumpSuspended ?? false {
            return LocalizedString("Resume delivery", comment: "Dana settings resume delivery")
        }
        
        if self.pumpManager?.state.isTempBasalInProgress ?? false {
            return LocalizedString("Stop temp basal", comment: "Dana settings stop temp basal")
        }
        
        return LocalizedString("Suspend delivery", comment: "Dana settings suspend delivery")
    }
}
