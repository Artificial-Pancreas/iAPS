//
//  BluetoothManager.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 14/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import CoreBluetooth
import Foundation
import LoopKit


let deviceNameRegex = try! NSRegularExpression(pattern: "^[a-zA-Z]{3}[0-9]{5}[a-zA-Z]{2}$")

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

protocol BluetoothManager : AnyObject, CBCentralManagerDelegate {
    var peripheral: CBPeripheral? { get set }
    var peripheralManager: PeripheralManager? { get set }
    
    var log: DanaLogger { get }
    
    var manager: CBCentralManager! { get }
    var managerQueue: DispatchQueue { get }
    var pumpManagerDelegate: DanaKitPumpManager? { get set }
    
    var autoConnectUUID: String? { get set }
    
    var connectionCompletion: ((ConnectionResult) -> Void)? { get set }
    var connectionCallback: [String: ((ConnectionResultShort) -> Void)] { get set }
    
    var devices: [DanaPumpScan] { get set }
    
    func disconnect(_ peripheral: CBPeripheral) -> Void
}

extension BluetoothManager {
    public var isConnected: Bool {
        self.peripheral?.state == .connected
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
            throw NSError(domain: "Invalid identifier - \(bleIdentifier)", code: -1)
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
    
    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol) {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }
        
        return try await peripheralManager.writeMessage(packet)
    }
    
    func resetConnectionCompletion() {
        self.connectionCompletion = nil
    }
    
    func finishV3Pairing(_ pairingKey: Data, _ randomPairingKey: Data) throws {
        guard let peripheralManager = self.peripheralManager else {
            throw NSError(domain: "No connected device", code: 0, userInfo: nil)
        }
        
        peripheralManager.finishV3Pairing(pairingKey, randomPairingKey)
    }
    
    func ensureConnected(_ completion: @escaping (ConnectionResultShort) async -> Void, _ identifier: String = #function) {
        self.connectionCallback[identifier] = { result in
            Task {
                self.resetConnectionCompletion()
                self.connectionCallback[identifier] = nil
                await completion(result)
            }
        }
        
        // Device still has an active connection with pump and is probably busy with something
        if self.isConnected {
            if self.pumpManagerDelegate?.state.isUsingContinuousMode ?? false {
                self.logDeviceCommunication("Dana - Connected", type: .connection)
                self.connectionCallback[identifier]!(.success)
            } else {
                self.logDeviceCommunication("Dana - Failed to connect: Already connected", type: .connection)
                self.connectionCallback[identifier]!(.failure)
            }
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
        } else if !self.isConnected && self.pumpManagerDelegate?.state.bleIdentifier != nil {
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

    private func startTimeout(seconds: TimeInterval, _ identifier: String) {
        Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds) * 1000000000)
                guard let connectionCallback = self.connectionCallback[identifier] else {
                    // This is amazing, we've done what we must and continue our live :)
                    return
                }
                
                self.logDeviceCommunication("Dana - Failed to connect: Timeout reached...", type: .connection)
                self.log.error("Failed to connect: Timeout reached...")
                
                connectionCallback(.failure)
                self.connectionCallback[identifier] = nil
            } catch{}
        }
    }
    
    internal func logDeviceCommunication(_ message: String, type: DeviceLogEntryType = .send) {
        let address = String(format: "%04X", self.pumpManagerDelegate?.state.bleIdentifier ?? "")
        // Not dispatching here; if delegate queue is blocked, timestamps will be delayed
        self.pumpManagerDelegate?.pumpDelegate.delegate?.deviceManager(self.pumpManagerDelegate!, logEventForDeviceIdentifier: address, type: type, message: message, completion: nil)
    }
    
}

// MARK: Central manager functions
extension BluetoothManager {
    func bleCentralManagerDidUpdateState(_ central: CBCentralManager) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        
        log.info("\(String(describing: central.state.rawValue))")
    }
    
    func bleCentralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        log.info("\(dict)")
    }
    
    func bleCentralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if (peripheral.name == nil || deviceNameRegex.firstMatch(in: peripheral.name!, range: NSMakeRange(0, peripheral.name!.count)) == nil) {
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
    
    func bleCentralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        dispatchPrecondition(condition: .onQueue(managerQueue))
        
        guard let connectionCompletion = self.connectionCompletion else {
            log.error("No connection callback found... Timeout hit probably")
            self.disconnect(peripheral)
            
            return
        }
        
        self.peripheral = peripheral
        self.peripheralManager = PeripheralManager(peripheral, self, self.pumpManagerDelegate!, connectionCompletion)
        
        self.pumpManagerDelegate?.state.deviceName = peripheral.name
        self.pumpManagerDelegate?.state.bleIdentifier = peripheral.identifier.uuidString
        self.pumpManagerDelegate?.notifyStateDidChange()
        
        peripheral.discoverServices([PeripheralManager.SERVICE_UUID])
    }
    
    func bleCentralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.info("Device disconnected, name: \(peripheral.name ?? "<NO_NAME>")")
        
        self.pumpManagerDelegate?.state.isConnected = false
        self.pumpManagerDelegate?.notifyStateDidChange()
        
        self.peripheral = nil
        self.peripheralManager = nil
        
        self.pumpManagerDelegate?.checkBolusDone()
    }
    
    func bleCentralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.info("Device connect error, name: \(peripheral.name ?? "<NO_NAME>"), error: \(error!.localizedDescription)")
    }
}
