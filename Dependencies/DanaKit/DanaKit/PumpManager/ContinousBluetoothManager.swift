//
//  ContinousBluetoothManager.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 09/06/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import CoreBluetooth

class ContinousBluetoothManager : NSObject, BluetoothManager {
    var pumpManagerDelegate: DanaKitPumpManager? {
        didSet {
            self.autoConnectUUID = self.pumpManagerDelegate?.state.bleIdentifier
        }
    }
    
    var autoConnectUUID: String? = nil
    var connectionCompletion: ((ConnectionResult) -> Void)? = nil
    var connectionCallback: [String: ((ConnectionResultShort) -> Void)] = [:]
    var devices: [DanaPumpScan] = []
    
    let log = DanaLogger(category: "ContinousBluetoothManager")
    var manager: CBCentralManager! = nil
    let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)
    
    var peripheral: CBPeripheral?
    var peripheralManager: PeripheralManager?
    
    override init() {
        super.init()
        
        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.DanaKit"])
        }
    }
    
    private func keepConnectionAlive() async {
        do {
            try await Task.sleep(nanoseconds: 45000000000) // Sleep for 45sec
            
            let keepAlivePacket = generatePacketGeneralKeepConnection()
            let result = try await self.writeMessage(keepAlivePacket)
            guard result.success else {
                self.log.error("Pump rejected keepAlive request: \(result.rawData.base64EncodedString())")
                return
            }
            
            Task {
                await self.keepConnectionAlive()
            }
        } catch {
            self.log.error("Failed to keep connection alive: \(error.localizedDescription)")
        }
    }
    
    public func reconnect() {
        if self.autoConnectUUID != nil && !self.isConnected {
            do {
                self.log.info("Auto-connect to \(String(describing: self.autoConnectUUID))")
                try self.connect(self.autoConnectUUID!) { result in
                    switch(result) {
                    case .success:
                        Task {
                            await self.keepConnectionAlive()
                        }
                        break;
                    default:
                        self.log.error("Failed to do auto connection: \(result)")
                    }
                }
            } catch {
                log.error("Failed to auto connect: \(error.localizedDescription)")
            }
        }
    }
    
    func disconnect(_ peripheral: CBPeripheral, force: Bool) {
        guard force else {
            return
        }
        
        self.autoConnectUUID = nil
        
        logDeviceCommunication("Dana - Disconnected", type: .connection)
        self.manager.cancelPeripheralConnection(peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bleCentralManagerDidUpdateState(central)
        
        if central.state == .poweredOn {
            self.reconnect()
        }
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        self.bleCentralManager(central, willRestoreState: dict)
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
