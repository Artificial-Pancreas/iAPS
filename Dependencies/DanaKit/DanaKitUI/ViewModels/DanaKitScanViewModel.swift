//
//  DanaKitScanViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 28/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import SwiftUI
import os.log
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
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?
     
    private let log = OSLog(category: "ScanView")
    private var pumpManager: DanaKitPumpManager?
    private var view: UIViewController?
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
            log.error("Failed to start scan action: %{public}@", error.localizedDescription)
        }
    }
    
    func setView(_ view: UIViewController) {
        self.view = view
    }
    
    func connect(_ item: ScanResultItem) {
        guard let device = self.foundDevices[item.bleIdentifier], let view = self.view else {
            log.error("No view or device...")
            return
        }
        
        self.stopScan()
        
        self.pumpManager?.connect(device, view, { error in self.connectComplete(error, device) })
        self.isConnecting = true
    }
    
    func connectComplete(_ error: Error?, _ peripheral: CBPeripheral) {
        self.isConnecting = false
        
        guard error == nil else {
            self.connectionErrorMessage = error?.localizedDescription ?? ""
            return
        }
        
        self.pumpManager?.disconnect(peripheral)
        self.nextStep()
    }
    
    func stopScan() {
        if !self.isScanning {
            return
        }
        
        self.pumpManager?.stopScan()
        self.isScanning = false
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
