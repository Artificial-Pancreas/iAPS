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
    
    override init() {
        super.init()
        
        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.DanaKit"])
        }
    }
    
    func disconnect(_ peripheral: CBPeripheral) {
        self.autoConnectUUID = nil
        
        logDeviceCommunication("Dana - Disconnected", type: .connection)
        self.manager.cancelPeripheralConnection(peripheral)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        self.bleCentralManagerDidUpdateState(central)
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
