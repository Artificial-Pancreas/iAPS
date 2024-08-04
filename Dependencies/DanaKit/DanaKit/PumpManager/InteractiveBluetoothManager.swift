//
//  InteractiveBluetoothManager.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/06/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit
import CoreBluetooth

class InteractiveBluetoothManager : NSObject, BluetoothManager {
    weak var pumpManagerDelegate: DanaKitPumpManager?
    
    var autoConnectUUID: String? = nil
    var connectionCompletion: ((ConnectionResult) -> Void)? = nil
    var connectionCallback: [String: ((ConnectionResultShort) -> Void)] = [:]
    var devices: [DanaPumpScan] = []
    
    let log = DanaLogger(category: "InteractiveBluetoothManager")
    var manager: CBCentralManager! = nil
    let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)
    
    var peripheral: CBPeripheral?
    var peripheralManager: PeripheralManager?
    
    public var isConnected: Bool {
        self.manager.state == .poweredOn && self.peripheral?.state == .connected
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
    
    func ensureConnected(_ completion: @escaping (ConnectionResultShort) async -> Void, _ identifier: String = #function) {
        self.connectionCallback[identifier] = { result in
            Task {
                self.resetConnectionCompletion()
                self.connectionCallback[identifier] = nil
                
                if result == .success {
                    do {
                        self.log.info("Sending keep alive message")
                        
                        let keepAlivePacket = generatePacketGeneralKeepConnection()
                        let _ = try await self.writeMessage(keepAlivePacket)
                    } catch {
                        self.log.error("Failed to send Keep alive message: \(error.localizedDescription)")
                    }
                    
                    await self.updateInitialState()
                }
                
                await completion(result)
            }
        }
        
        // Device still has an active connection with pump and is probably busy with something
        if self.isConnected {
            self.logDeviceCommunication("Dana - Failed to connect: Already connected", type: .connection)
            self.connectionCallback[identifier]!(.failure)
            
        // We stored the peripheral. We can quickly reconnect
        } else if self.peripheral != nil {
            self.startTimeout(seconds: TimeInterval.seconds(15), identifier)
            
            self.connect(self.peripheral!) { result in
                guard let connectionCallback = self.connectionCallback[identifier] else {
                    // We've already hit the timeout function above
                    // Exit if we every hit this...
                    return
                }
                
                switch result {
                case .success:
                    self.logDeviceCommunication("Dana - Connected", type: .connection)
                    connectionCallback(.success)
                case .failure(let err):
                    self.logDeviceCommunication("Dana - Failed to connect: " + err.localizedDescription, type: .connection)
                    connectionCallback(.failure)
                case .requestedPincode:
                    self.logDeviceCommunication("Dana - Requested pincode", type: .connection)
                    connectionCallback(.failure)
                case .invalidBle5Keys:
                    self.logDeviceCommunication("Dana - Invalid ble 5 keys", type: .connection)
                    connectionCallback(.failure)
                }
            }
            // No active connection and no stored peripheral. We have to scan for device before being able to send command
        } else if self.pumpManagerDelegate?.state.bleIdentifier != nil {
            do {
                self.startTimeout(seconds: TimeInterval.seconds(30), identifier)
                
                try self.connect(self.pumpManagerDelegate!.state.bleIdentifier!) { result in
                    guard let connectionCallback = self.connectionCallback[identifier] else {
                        // We've already hit the timeout function above
                        // Exit if we every hit this...
                        return
                    }
                    
                    switch result {
                    case .success:
                        self.logDeviceCommunication("Dana - Connected", type: .connection)
                        connectionCallback(.success)
                    case .failure(let err):
                        self.logDeviceCommunication("Dana - Failed to connect: " + err.localizedDescription, type: .connection)
                        connectionCallback(.failure)
                    case .requestedPincode:
                        self.logDeviceCommunication("Dana - Requested pincode", type: .connection)
                        connectionCallback(.failure)
                    case .invalidBle5Keys:
                        self.logDeviceCommunication("Dana - Invalid ble 5 keys", type: .connection)
                        connectionCallback(.failure)
                    }
                }
            } catch {
                self.logDeviceCommunication("Dana - Failed to connect: " + error.localizedDescription, type: .connection)
                self.connectionCallback[identifier]?(.failure)
            }
            
            // Should never reach, but is only possible if device is not onboard (we have no ble identifier to connect to)
        } else {
            self.log.error("Pump is not onboarded")
            self.logDeviceCommunication("Dana - Pump is not onboarded", type: .connection)
            self.connectionCallback[identifier]!(.failure)
        }
    }
    
    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }
        
        return try await peripheralManager.writeMessage(packet)
    }
    
    func disconnect(_ peripheral: CBPeripheral, force: Bool) {
        self.autoConnectUUID = nil
        
        logDeviceCommunication("Dana - Disconnected", type: .connection)
        self.manager.cancelPeripheralConnection(peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bleCentralManagerDidUpdateState(central)
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        self.bleCentralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        self.bleCentralManager(central, didConnect: peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.bleCentralManager(central, didDisconnectPeripheral: peripheral, error: error)
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        self.bleCentralManager(central, didFailToConnect: peripheral, error: error)
    }
}
