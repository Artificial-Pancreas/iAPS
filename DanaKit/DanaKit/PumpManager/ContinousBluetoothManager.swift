//
//  ContinousBluetoothManager.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 09/06/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import CoreBluetooth
import BackgroundTasks
import UserNotifications

class ContinousBluetoothManager : NSObject, BluetoothManager {
    var pumpManagerDelegate: DanaKitPumpManager? {
        didSet {
            self.autoConnectUUID = self.pumpManagerDelegate?.state.bleIdentifier
        }
    }
    
    var autoConnectUUID: String? = nil
    var connectionCompletion: ((ConnectionResult) -> Void)? = nil
    var connectionCallback: [String: ((ConnectionResult) -> Void)] = [:]
    var devices: [DanaPumpScan] = []
    
    let log = DanaLogger(category: "ContinousBluetoothManager")
    var manager: CBCentralManager! = nil
    let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)
    
    var peripheral: CBPeripheral?
    var peripheralManager: PeripheralManager?
    var forcedDisconnect = false
    
    public var isConnected: Bool {
        self.manager.state == .poweredOn && self.peripheral?.state == .connected && self.pumpManagerDelegate?.state.isConnected ?? false
    }
    
    override init() {
        super.init()
        
        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue)
        }
    }
    
    deinit {
        self.manager = nil
    }
    
    private func handleBackgroundTask() {
        Task {
            while isConnected {
                await keepConnectionAlive()
                try await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
            }

            self.log.warning("Existed background job. Not connected anymore")
        }
    }
    
    private func keepConnectionAlive() async {
        do {
            if self.pumpManagerDelegate?.status.bolusState == .noBolus {
                self.log.info("Sending keep alive message")
                let keepAlivePacket = generatePacketGeneralKeepConnection()
                let result = try await self.writeMessage(keepAlivePacket)
                guard result.success else {
                    self.log.error("Pump rejected keepAlive request: \(result.rawData.base64EncodedString())")
                    return
                }
            } else {
                self.log.info("Skip sending keep alive message. Reason: bolus is running")
            }
        } catch {
            self.log.error("Failed to keep connection alive: \(error.localizedDescription)")
        }
    }
    
    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard let peripheralManager = self.peripheralManager, isConnected else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }
        
        return try await peripheralManager.writeMessage(packet)
    }
    
    public func reconnect(_ callback: @escaping (Bool) -> Void) {
        guard !self.isConnected else{
            callback(true)
            return
        }
        
        NotificationHelper.setDisconnectWarning()
        if self.autoConnectUUID == nil {
            self.autoConnectUUID = self.pumpManagerDelegate?.state.bleIdentifier
        }
        
        if self.peripheral != nil {
            self.connect(self.peripheral!) { result in
                switch(result) {
                case .success:
                    self.forcedDisconnect = false
                    Task {
                        await self.updateInitialState()
                        self.handleBackgroundTask()
                        callback(true)
                    }
                    break;
                default:
                    self.log.error("Failed to reconnect: \(result)")
                    callback(false)
                }
            }
            return
        }
        
        guard let autoConnect = self.autoConnectUUID else {
            self.log.error("No autoConnect: \(String(describing: self.autoConnectUUID))")
            callback(false)
            return
        }
        
        do {
            try self.connect(autoConnect) { result in
                switch(result) {
                case .success:
                    self.forcedDisconnect = false
                    Task {
                        await self.updateInitialState()
                        self.handleBackgroundTask()
                        callback(true)
                    }
                    break;
                default:
                    self.log.error("Failed to do auto connection: \(result)")
                    callback(false)
                }
            }
        } catch {
            log.error("Failed to auto connect: \(error.localizedDescription)")
            callback(false)
        }
    }
    
    func ensureConnected(_ completion: @escaping (ConnectionResult) async -> Void, _ identifier: String = #function) {
        if self.isConnected {
            self.resetConnectionCompletion()
            self.logDeviceCommunication("Dana - Connection is ok!", type: .connection)
            Task {
                await self.updateInitialState()
                await completion(.success)
            }
            
        } else if !self.forcedDisconnect {
            self.reconnect { result in
                guard result else {
                    self.log.error("Failed to reconnect")
                    self.logDeviceCommunication("Dana - Couldn't reconnect", type: .connection)
                    
                    self.resetConnectionCompletion()
                    Task {
                        await completion(.failure(NSError(domain: "Couldn't reconnect", code: -1)))
                    }
                    return
                }
                
                self.resetConnectionCompletion()
                self.logDeviceCommunication("Dana - Reconnected!", type: .connection)
                Task {
                    await self.updateInitialState()
                    await completion(.success)
                }
            }
        } else {
            // We aren't connected, the user has disconnected the pump by hand
            self.log.warning("Device is forced disconnected...")
            self.logDeviceCommunication("Dana - Pump is not connected. Please reconnect to pump before doing any operations", type: .connection)
            
            self.resetConnectionCompletion()
            Task {
                await completion(.failure(NSError(domain: "Device is forced disconnected...", code: -1)))
            }
        }
    }
    
    func disconnect(_ peripheral: CBPeripheral, force: Bool) {
        guard force else {
            return
        }
        
        self.autoConnectUUID = nil
        self.forcedDisconnect = true
        
        logDeviceCommunication("Dana - Disconnected", type: .connection)
        self.manager.cancelPeripheralConnection(peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bleCentralManagerDidUpdateState(central)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if central.state == .poweredOn {
                self.reconnect { result in
                    guard result else {
                        return
                    }

                    self.log.info("Reconnected and sync pump data!")
                    self.pumpManagerDelegate?.syncPump { _ in }
                }
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.bleCentralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.bleCentralManager(central, didConnect: peripheral)
        
        NotificationHelper.clearDisconnectWarning()
        NotificationHelper.clearDisconnectReminder()
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.bleCentralManager(central, didDisconnectPeripheral: peripheral, error: error)
        
        guard !self.forcedDisconnect else {
            // Dont reconnect if the user has manually disconnected
            return
        }
        
        self.reconnect { result in
            guard result else {
                return
            }

            self.log.info("Reconnected and sync pump data!")
            self.pumpManagerDelegate?.syncPump { _ in }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.bleCentralManager(central, didFailToConnect: peripheral, error: error)
    }
}
