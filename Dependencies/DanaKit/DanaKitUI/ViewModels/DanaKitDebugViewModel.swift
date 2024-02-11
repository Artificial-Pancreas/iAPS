//
//  DanaKitDebugViewModel.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 19/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import SwiftUI
import os.log
import LoopKit

class DanaKitDebugViewModel : ObservableObject {
    @Published var scannedDevices: [DanaPumpScan] = []
    
    @Published var isPresentingTempBasalAlert = false
    @Published var isPresentingScanAlert = false
    @Published var isPresentingBolusAlert = false
    @Published var isPresentingScanningErrorAlert = false
    @Published var scanningErrorMessage = ""
    @Published var connectedDeviceName = ""
    @Published var messageScanAlert = ""
    @Published var isConnected = false
    @Published var isConnectionError = false
    @Published var connectionErrorMessage: String?
    
    private let log = OSLog(category: "DebugView")
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
    
    func connectCompletion(_ error: Error?) {
        guard error == nil else {
            self.isConnectionError = true
            self.connectionErrorMessage = error?.localizedDescription ?? ""
            return
        }
        
        self.isConnected = true
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
    
    func getLogs() -> String {
        let logs = log.getDebugLogs()
        print(logs)
        return logs
    }
}

extension DanaKitDebugViewModel: StateObserver {
    func deviceScanDidUpdate(_ device: DanaPumpScan) {
        log.default("Found device %{public}@", device.name)
        self.scannedDevices.append(device)
        
        messageScanAlert = "Do you want to connect to: " + device.name + " (" + device.bleIdentifier + ")"
        isPresentingScanAlert = true
        
    }
    
    func stateDidUpdate(_ state: DanaKitPumpManagerState, _ oldState: DanaKitPumpManagerState) {
        self.isConnected = state.isConnected
        self.connectedDeviceName = state.deviceName ?? ""
    }
}
