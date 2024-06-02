//
//  BluetoothManager.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 14/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import CoreBluetooth
import Foundation

public enum ConnectionResult {
    case success
    case requestedPincode(String?)
    case invalidBle5Keys
    case failure(Error)
}

public struct DanaPumpScan {
    let bleIdentifier: String
    let name: String
    let peripheral: CBPeripheral
}

enum EncryptionType: UInt8 {
    case DEFAULT = 0
    case RSv3 = 1
    case BLE_5 = 2
}

class BluetoothManager : NSObject {
    
    private let log = DanaLogger(category: "BluetoothManager")
    
    private var autoConnectUUID: String?
    private let deviceNameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z]{3}[0-9]{5}[a-zA-Z]{2}$")
    
    private var manager: CBCentralManager! = nil
    private let managerQueue = DispatchQueue(label: "com.DanaKit.bluetoothManagerQueue", qos: .unspecified)
    
    public var pumpManagerDelegate: DanaKitPumpManager?
    private(set) var peripheral: CBPeripheral?
    private var peripheralManager: PeripheralManager?
    
    private var connectionCompletion: ((ConnectionResult) -> Void)?
    
    private var devices: [DanaPumpScan] = []
    
    public var isConnected: Bool {
        self.peripheralManager != nil
    }

    override init() {
        super.init()
        
        managerQueue.sync {
            self.manager = CBCentralManager(delegate: self, queue: managerQueue, options: [CBCentralManagerOptionRestoreIdentifierKey: "com.DanaKit"])
        }
    }
    
    func startScan() throws {
        guard self.manager.state == .poweredOn else {
            throw NSError(domain: "Invalid bluetooth state. State: " + String(self.manager.state.rawValue), code: 0, userInfo: nil)
        }
        
        guard !self.manager.isScanning else {
            log.info("Device is already scanning...")
            return
        }
        
        self.devices = []
        
        manager.scanForPeripherals(withServices: [])
        log.info("Started scanning")
    }
    
    func stopScan() {
        manager.stopScan()
        self.devices = []
        
        log.info("Stopped scanning")
    }
    
    func connect(_ bleIdentifier: String, _ completion: @escaping (ConnectionResult) -> Void) throws {
        guard let identifier = UUID(uuidString: bleIdentifier) else {
            log.error("Invalid identifier - \(bleIdentifier)")
            return
        }
        
        self.connectionCompletion = completion
        
        let peripherals = manager.retrievePeripherals(withIdentifiers: [identifier])
        if let peripheral = peripherals.first {
            DispatchQueue.main.async {
                self.peripheral = peripheral
                self.peripheralManager = PeripheralManager(peripheral, self, self.pumpManagerDelegate!, completion)
                
                self.manager.connect(peripheral, options: nil)
            }
            return
        }
        
        self.autoConnectUUID = bleIdentifier
        try self.startScan()
        
        // throw error if device could not be found after 10 sec
        Task {
            try? await Task.sleep(nanoseconds: 10000000000)
            guard self.peripheral != nil else {
                throw NSError(domain: "Device is not findable", code: -1)
            }
        }
    }
    
    func connect(_ peripheral: CBPeripheral, _ completion: @escaping (ConnectionResult) -> Void) {
        if self.peripheral != nil {
            self.disconnect(self.peripheral!)
        }
        
        manager.connect(peripheral, options: nil)
        self.connectionCompletion = completion
    }
    
    func disconnect(_ peripheral: CBPeripheral) {
        self.autoConnectUUID = nil
        self.manager.cancelPeripheralConnection(peripheral)
    }
    
    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }
        
        return try await peripheralManager.writeMessage(packet)
    }
    
    func updateInitialState() async throws {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }
        
        return await peripheralManager.updateInitialState()
    }
    
    func resetConnectionCompletion() {
        self.connectionCompletion = nil
    }
    
    func finishV3Pairing(_ pairingKey: Data, _ randomPairingKey: Data) {
        peripheralManager?.finishV3Pairing(pairingKey, randomPairingKey)
    }
}

// MARK: Central manager functions
extension BluetoothManager : CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        
        log.info("\(String(describing: central.state.rawValue))")
    }
    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        log.info("\(dict)")
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if (peripheral.name == nil || self.deviceNameRegex.firstMatch(in: peripheral.name!, range: NSMakeRange(0, peripheral.name!.count)) == nil) {
            return
        }
        
        dispatchPrecondition(condition: .onQueue(managerQueue))
        log.info("\(peripheral), \(advertisementData)")
        
        if self.autoConnectUUID != nil && peripheral.identifier.uuidString == self.autoConnectUUID {
            self.stopScan()
            self.connect(peripheral, self.connectionCompletion!)
            return
        }
        
        let device: DanaPumpScan? = devices.first(where: { $0.bleIdentifier == peripheral.identifier.uuidString })
        if (device != nil) {
            return
        }
        
        let result = DanaPumpScan(bleIdentifier: peripheral.identifier.uuidString, name: peripheral.name!, peripheral: peripheral)
        devices.append(result)
        self.pumpManagerDelegate?.notifyScanDeviceDidChange(result)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        
        guard let connectionCompletion = self.connectionCompletion else {
            log.error("No connection callback found... Timeout hit probably")
            self.disconnect(peripheral)
            
            return
        }
        
        
        DispatchQueue.main.async {
            self.peripheral = peripheral
            self.peripheralManager = PeripheralManager(peripheral, self, self.pumpManagerDelegate!, connectionCompletion)
            
            self.pumpManagerDelegate?.state.deviceName = peripheral.name
            self.pumpManagerDelegate?.state.bleIdentifier = peripheral.identifier.uuidString
            self.pumpManagerDelegate?.notifyStateDidChange()
            
            peripheral.discoverServices([PeripheralManager.SERVICE_UUID])
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.info("Device disconnected, name: \(peripheral.name ?? "<NO_NAME>")")
        
        self.pumpManagerDelegate?.state.isConnected = false
        self.pumpManagerDelegate?.notifyStateDidChange()
        
        self.peripheral = nil
        self.peripheralManager = nil
        
        self.pumpManagerDelegate?.checkBolusDone()
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.info("Device connect error, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error!.localizedDescription)")
    }
}
