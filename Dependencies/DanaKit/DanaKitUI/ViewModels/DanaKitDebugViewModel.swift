//
//  DanaKitDebugViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 19/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKit

class DanaKitDebugViewModel : ObservableObject {
    @Published var scannedDevices: [DanaPumpScan] = []
    
    @Published var isPresentingTempBasalAlert = false
    @Published var isPresentingScanAlert = false
    @Published var isPresentingBolusAlert = false
    @Published var isPresentingScanningErrorAlert = false
    @Published var isPromptingPincode = false
    @Published var pinCodePromptError: String?
    @Published var scanningErrorMessage = ""
    @Published var connectedDeviceName = ""
    @Published var messageScanAlert = ""
    @Published var isConnected = false
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?
    
    @Published var pin1 = ""
    @Published var pin2 = ""
    
    private let log = DanaLogger(category: "DebugView")
    private var pumpManager: DanaKitPumpManager?
    private var connectedDevice: DanaPumpScan?
    
    init(_ pumpManager: DanaKitPumpManager? = nil) {
        self.pumpManager = pumpManager
        
        self.pumpManager?.addScanDeviceObserver(self, queue: .main)
        self.pumpManager?.addStateObserver(self, queue: .main)
    }
    
    func scan() {
        do {
            try self.pumpManager?.startScan()
        } catch {
            self.isPresentingScanningErrorAlert = true
            self.scanningErrorMessage = error.localizedDescription
        }
    }
    
    func connect() {
        guard let device = scannedDevices.last else {
            log.error("No view or device...")
            return
        }
        
        self.pumpManager?.stopScan()
        self.pumpManager?.connect(device.peripheral, connectCompletion)
        self.connectedDevice = device
    }
    
    func connectCompletion(_ result: ConnectionResult) {
        switch result {
        case .success:
            self.isConnected = true
            
        case .failure(let error):
            self.isConnectionError = true
            self.connectionErrorMessage = error.localizedDescription
            
        case .invalidBle5Keys:
            self.isConnectionError = true
            self.connectionErrorMessage = LocalizedString("Failed to pair to ", comment: "Dana-i failed to pair p1") + (self.pumpManager?.state.deviceName ?? "<NO_NAME>") + LocalizedString(". Please go to your bluetooth settings, forget this device, and try again", comment: "Dana-i failed to pair p2")
            
        case .requestedPincode(let message):
            self.isPromptingPincode = true
            self.pinCodePromptError = message
        }
    }
    
    func cancelPinPrompt() {
        self.isPromptingPincode = false
        self.pumpManager?.disconnect()
    }
    
    func processPinPrompt() {
        guard pin1.count == 12, pin2.count == 8 else {
            self.pinCodePromptError = LocalizedString("Received invalid pincode lengths. Try again", comment: "Dana-RS v3 pincode prompt error invalid length")
            self.isPromptingPincode = true
            return
        }
        
        guard let pin1 = Data(hexString: pin1), let pin2 = Data(hexString: pin2) else {
            self.pinCodePromptError = LocalizedString("Received invalid hex strings. Try again", comment: "Dana-RS v3 pincode prompt error invalid hex")
            self.isPromptingPincode = true
            return
        }
        
        let randomPairingKey = pin2.prefix(3)
        let checkSum = pin2.dropFirst(3).prefix(1)
        
        var pairingKeyCheckSum: UInt8 = 0
        for byte in pin1 {
            pairingKeyCheckSum ^= byte
        }
        
        for byte in randomPairingKey {
            pairingKeyCheckSum ^= byte
        }
        
        guard checkSum.first == pairingKeyCheckSum else {
            self.pinCodePromptError = LocalizedString("Checksum failed. Try again", comment: "Dana-RS v3 pincode prompt error checksum failed")
            self.isPromptingPincode = true
            return
        }
        
        self.pumpManager?.finishV3Pairing(pin1, randomPairingKey)
    }
    
    func bolusModal() {
        self.isPresentingBolusAlert = true
    }
    
    func bolus() {
        self.pumpManager?.enactBolus(units: 5.0, activationType: .manualNoRecommendation, completion: bolusCompletion)
        self.isPresentingBolusAlert = false
    }
    
    func bolusCompletion(_ error: PumpManagerError?) {
        if (error == nil) {
            return
        }
        
        log.error("Bolus failed...")
    }
    
    func stopBolus() {
        self.pumpManager?.cancelBolus(completion: bolusCancelCompletion)
    }
    
    func bolusCancelCompletion(_ result: PumpManagerResult<DoseEntry?>) {
        if case .success = result {
            return
        } else {
            log.error("Cancel failed...")
        }
    }
    
    func tempBasalModal() {
        self.isPresentingTempBasalAlert = true
    }

    func tempBasal() {
        // 200% temp basal for 2 hours
        self.pumpManager?.enactTempBasal(unitsPerHour: 1, for: 7200, completion: tempBasalCompletion)
        self.isPresentingTempBasalAlert = false
    }
    
    func tempBasalCompletion(_ error: PumpManagerError?) {
        if (error == nil) {
            return
        }
        
        log.error("Temp basal failed...")
    }
    
    func stopTempBasal() {
        self.pumpManager?.enactTempBasal(unitsPerHour: 0, for: 0, completion: tempBasalCompletion)
    }
    
    func basal() {
        let basal = Array(0..<24).map({ RepeatingScheduleValue<Double>(startTime: TimeInterval(60 * 30 * $0), value: 0.5) })
        self.pumpManager?.syncBasalRateSchedule(items: basal, completion: basalCompletion)
    }
    
    func basalCompletion(_ result: Result<DailyValueSchedule<Double>, any Error>) {
        if case .success = result {
            return
        } else {
            log.error("Cancel failed...")
        }
    }
    
    func disconnect() {
        guard let device = self.connectedDevice else {
            return
        }
        
        self.pumpManager?.disconnect(device.peripheral)
    }
    
    func getLogs() -> [URL] {
        return log.getDebugLogs()
    }
}

extension DanaKitDebugViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: DanaPumpScan) {
        log.info("Found device \(device.name)")
        self.scannedDevices.append(device)
        
        messageScanAlert = "Do you want to connect to: " + device.name + " (" + device.bleIdentifier + ")"
        isPresentingScanAlert = true
        
    }
    
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _ oldState: DanaKitPumpManagerState) {
        self.isConnected = state.isConnected
        self.connectedDeviceName = state.deviceName ?? ""
    }
}
