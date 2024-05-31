//
//  DanaKitScanViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 28/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import SwiftUI
import LoopKit
import CoreBluetooth

struct ScanResultItem: Identifiable {
    let id = UUID()
    var name: String
    let bleIdentifier: String
}

class DanaKitScanViewModel : ObservableObject {
    @Published var scannedDevices: [ScanResultItem] = []
    @Published var isScanning = false
    @Published var isConnecting = false
    @Published var connectingTo: String? = nil
    @Published var isPromptingPincode = false
    @Published var pinCodePromptError: String?
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?
    
    @Published var pin1 = ""
    @Published var pin2 = ""
     
    private let log = DanaLogger(category: "ScanView")
    private var pumpManager: DanaKitPumpManager?
    private var nextStep: () -> Void
    private var foundDevices: [String:CBPeripheral] = [:]
    
    init(_ pumpManager: DanaKitPumpManager? = nil, nextStep: @escaping () -> Void) {
        self.pumpManager = pumpManager
        self.nextStep = nextStep
        
        self.pumpManager?.addScanDeviceObserver(self, queue: .main)
        self.pumpManager?.addStateObserver(self, queue: .main)
        
        do {
            try self.pumpManager?.startScan()
            self.isScanning = true
        } catch {
            log.error("\(#function): Failed to start scan action: \(error.localizedDescription)")
        }
    }
    
    func connect(_ item: ScanResultItem) {
        guard let device = self.foundDevices[item.bleIdentifier] else {
            log.error("No view or device...")
            return
        }
        
        self.stopScan()
        self.connectingTo = item.name
        
        self.pumpManager?.connect(device) { result in
            DispatchQueue.main.async {
                self.connectComplete(result, device)
            }
        }
        self.isConnecting = true
    }
    
    func connectComplete(_ result: ConnectionResult, _ peripheral: CBPeripheral) {
        switch result {
        case .success:
            self.pumpManager?.disconnect(peripheral)
            self.nextStep()
            
        case .failure(let e):
            self.isConnecting = false
            self.connectionErrorMessage = e.localizedDescription
            
        case .invalidBle5Keys:
            self.isConnecting = false
            self.connectionErrorMessage = LocalizedString("Failed to pair to ", comment: "Dana-i failed to pair p1") + (self.pumpManager?.state.deviceName ?? "<NO_NAME>") + LocalizedString(". Please go to your bluetooth settings, forget this device, and try again", comment: "Dana-i failed to pair p2")
            
        case .requestedPincode(let message):
            self.isConnecting = true
            self.isPromptingPincode = true
            self.pinCodePromptError = message
        }
    }
    
    func stopScan() {
        self.pumpManager?.stopScan()
        self.isScanning = false
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
}

extension DanaKitScanViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: DanaPumpScan) {
        self.scannedDevices.append(ScanResultItem(name: device.name, bleIdentifier: device.bleIdentifier))
        self.foundDevices[device.bleIdentifier] = device.peripheral
    }
    
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _ oldState: DanaKitPumpManagerState) {
        // Not needed
    }
}
