//
//  PeripheralManager.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 21/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import CoreBluetooth
import os.log
import SwiftUI

class PeripheralManager: NSObject {
    private let log = DanaLogger(category: "PeripheralManager")
    
    private let connectedDevice: CBPeripheral
    private let bluetoothManager: BluetoothManager
    private var completion: ((ConnectionResult) -> Void)?
    
    private var pumpManager: DanaKitPumpManager
    private var readBuffer = Data([])
    
    private let okCharCodes: [UInt8] = [0x4f, 0x4b] // O, K
    private let pumpCharCodes: [UInt8] = [0x50, 0x55, 0x4d, 0x50] // P, U, M, P
    private let busyCharCodes: [UInt8] = [0x42, 0x55, 0x53, 0x59] // B, U, S, Y
    
    private let PACKET_START_BYTE: UInt8 = 0xa5
    private let PACKET_END_BYTE: UInt8 = 0x5a
    private let ENCRYPTED_START_BYTE: UInt8 = 0xaa
    private let ENCRYPTED_END_BYTE: UInt8 = 0xee
    
    public static let SERVICE_UUID = CBUUID(string: "FFF0")
    private let READ_CHAR_UUID = CBUUID(string: "FFF1")
    private var readCharacteristic: CBCharacteristic!
    private let WRITE_CHAR_UUID = CBUUID(string: "FFF2")
    private var writeCharacteristic: CBCharacteristic!
    
    private var writeQueue: Dictionary<UInt8, CheckedContinuation<(any DanaParsePacketProtocol), Error>> = [:]
    private var writeTimeoutTask: Task<(), Never>?
    private let writeSemaphore = DispatchSemaphore(value: 1)
    
    private var historyLog: [HistoryItem] = []
    
    private var deviceName: String {
        get {
            return self.pumpManager.state.deviceName ?? ""
        }
    }
    
    public init(_ peripheral: CBPeripheral, _ bluetoothManager: BluetoothManager, _ pumpManager: DanaKitPumpManager,_ completion: @escaping (ConnectionResult) -> Void) {
        self.connectedDevice = peripheral
        self.bluetoothManager = bluetoothManager
        self.pumpManager = pumpManager
        self.completion = completion
        
        super.init()
        
        peripheral.delegate = self
    }
    
    deinit {
        self.writeTimeoutTask?.cancel()
        
        for (opCode, continuation) in self.writeQueue {
            continuation.resume(throwing: NSError(domain: "PeripheralManager deinit hit... Most likely an encryption issue - opCode: \(opCode)", code: 0, userInfo: nil))
        }
    }
    
    func writeMessage(_ packet: DanaGeneratePacket) async throws -> (any DanaParsePacketProtocol)  {
        return try await withCheckedThrowingContinuation { continuation in
            self.writeQueue[packet.opCode] = continuation
            self.write(packet)
        }
    }
    
    private func write(_ packet: DanaGeneratePacket) {
        self.writeSemaphore.wait()
        
        let command = (UInt16((packet.type ?? DanaPacketType.TYPE_RESPONSE)) << 8) + UInt16(packet.opCode)
        
        // Make sure we have the correct state
        if (packet.opCode == CommandGeneralSetHistoryUploadMode && packet.data != nil) {
            self.pumpManager.state.isInFetchHistoryMode = packet.data![0] == 0x01
        } else {
            self.pumpManager.state.isInFetchHistoryMode = false
        }
        
        
        var data = DanaRSEncryption.encodePacket(operationCode: packet.opCode, buffer: packet.data, deviceName: self.deviceName)
//        self.log.info("Sending opCode: \(packet.opCode), encrypted data: \(data.base64EncodedString()), randomSyncKey: \(DanaRSEncryption.randomSyncKey)")
        
        if (DanaRSEncryption.enhancedEncryption != EncryptionType.DEFAULT.rawValue) {
            data = DanaRSEncryption.encodeSecondLevel(data: data)
//            self.log.info("Second level encrypted data: \(data.base64EncodedString())")
        }
        
        // Now schedule a 6 sec timeout (or 21 when in fetchHistoryMode) for the pump to send its message back
        // This timeout will be cancelled by `processMessage` once it received the message
        // If this timeout expired, disconnect from the pump and prompt an error...
        let isHistoryPacket = self.isHistoryPacket(opCode: command)
        while (data.count != 0) {
            let end = min(20, data.count)
            let message = data.subdata(in: 0..<end)
            
            self.writeQ(message)
            data = data.subdata(in: end..<data.count)
        }
        
        self.writeTimeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(!isHistoryPacket ? .seconds(4) : .seconds(21)) * 1_000_000_000)
                guard let queueItem = self.writeQueue[packet.opCode] else {
                    // We did what we must, so exist and be happy :)
                    return
                }
                
                // We hit a timeout
                // This means the pump received the message but could decrypt it
                // We need to reconnect in order to fix the encryption keys
                self.bluetoothManager.manager.cancelPeripheralConnection(self.connectedDevice)
                queueItem.resume(throwing: NSError(domain: "Message write timeout. Most likely an encryption issue - opCode: \(packet.opCode)", code: 0, userInfo: nil))
                
                self.writeQueue[packet.opCode] = nil
                self.writeTimeoutTask = nil
                self.writeSemaphore.signal()
            } catch {
                // Task was cancelled because message has been received
            }
        }
    }
    
    private func connectionFailure(_ error: any Error) {
        self.bluetoothManager.manager.cancelPeripheralConnection(self.connectedDevice)
        
        guard let completion = self.completion else {
            return
        }
        
        DispatchQueue.main.async {
            completion(.failure(error))
        }
    }
}

extension PeripheralManager : CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }
        
        let service = peripheral.services?.first(where: { $0.uuid == PeripheralManager.SERVICE_UUID })
        if (service == nil) {
            log.error("Failed to discover dana data service...")
            connectionFailure(NSError(domain: "Failed to discover dana data service...", code: 0, userInfo: nil))
            return
        }
        
//        log.info("Discovered service \(PeripheralManager.SERVICE_UUID)")
        
        peripheral.discoverCharacteristics([READ_CHAR_UUID, WRITE_CHAR_UUID], for: service!)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }
        
        let service = peripheral.services!.first(where: { $0.uuid == PeripheralManager.SERVICE_UUID })!
        self.readCharacteristic = service.characteristics?.first(where: { $0.uuid == READ_CHAR_UUID })
        self.writeCharacteristic = service.characteristics?.first(where: { $0.uuid == WRITE_CHAR_UUID })
        
        if (self.writeCharacteristic == nil || self.readCharacteristic == nil) {
            log.error("Failed to discover dana write or read characteristic")
            connectionFailure(NSError(domain: "Failed to discover dana write or read characteristic", code: 0, userInfo: nil))
            return
        }
        
//        log.info("Discovered characteristics \(READ_CHAR_UUID) and \(WRITE_CHAR_UUID)")
        peripheral.setNotifyValue(true, for: self.readCharacteristic)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)  {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }
        
//        log.info("Notifications has been enabled. Sending starting handshake")
        self.sendFirstMessageEncryption()
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            log.error("\(error!.localizedDescription)")
            connectionFailure(error!)
            return
        }
        
        guard let data = characteristic.value else {
            return
        }
        
//        log.info("Receiving data: \(data.base64EncodedString())")
        self.parseReceivedValue(data)
    }
    
    private func writeQ(_ data: Data) {
//        log.info("Writing data \(data.base64EncodedString())")
        self.connectedDevice.writeValue(data, for: self.writeCharacteristic, type: .withoutResponse)
    }
}

// MARK: - Encryption/Connection functions
extension PeripheralManager {
    private func sendFirstMessageEncryption() {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__PUMP_CHECK, buffer: nil, deviceName: self.deviceName)
        
//        log.info("Sending Initial encryption request. Data: \(data.base64EncodedString())")
        self.writeQ(data)
    }
    
    private func sendTimeInfo() {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION, buffer: nil, deviceName: self.deviceName)
        
//        log.info("Sending normal time information. Data: \(data.base64EncodedString())")
        self.writeQ(data)
    }
    
    private func sendV3PairingInformation(_ requestNewPairing: UInt8) {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION, buffer: Data([requestNewPairing]), deviceName: self.deviceName)
        
//        log.info("Sending RSv3 time information. Data: \(data.base64EncodedString())")
        self.writeQ(data)
    }
    
    // 0x00 Start encryption, 0x01 Request pairing
    private func sendV3PairingInformationEmpty() {
        var (pairingKey, randomPairingKey) = DanaRSEncryption.getPairingKeys()
        if pairingKey.filter({ $0 != 0 }).count == 0 || randomPairingKey.filter({ $0 != 0 }).count == 0 {
            pairingKey = self.pumpManager.state.pairingKey
            randomPairingKey = self.pumpManager.state.randomPairingKey
            
            if pairingKey.filter({ $0 != 0 }).count == 0 || randomPairingKey.filter({ $0 != 0 }).count == 0 {
                self.sendV3PairingInformation(1)
                return
            }
        }
        
        let randomSyncKey = self.pumpManager.state.randomSyncKey
//        self.log.info("Setting encryption keys. Pairing key: \(pairingKey.base64EncodedString()), random pairing key: \(randomPairingKey.base64EncodedString()), random sync key: \(randomSyncKey)")
        DanaRSEncryption.setPairingKeys(pairingKey: pairingKey, randomPairingKey: randomPairingKey, randomSyncKey: randomSyncKey)
        
        self.sendV3PairingInformation(0)
    }
    
    private func sendPairingRequest() {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_REQUEST, buffer: nil, deviceName: self.deviceName)
        
//        log.info("Sending pairing request. Data: \(data.base64EncodedString())")
        self.writeQ(data)
    }
    
    private func sendEasyMenuCheck() {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__GET_EASYMENU_CHECK, buffer: nil, deviceName: self.deviceName)
        
//        log.info("Sending easy menu check. Data: \(data.base64EncodedString())")
        self.writeQ(data)
    }
    
    private func sendBLE5PairingInformation() {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION, buffer: Data([0, 0, 0, 0]), deviceName: self.deviceName)
        
//        log.info("Sending BLE5 time information. Data: \(Data([0, 0, 0, 0]).base64EncodedString())")
        self.writeQ(data)
    }
    
    private func sendPassKeyCheck(_ pairingKey: Data) {
        let data = DanaRSEncryption.encodePacket(operationCode: DanaPacketType.OPCODE_ENCRYPTION__CHECK_PASSKEY, buffer: pairingKey, deviceName: self.deviceName)
        
//        log.info("Sending Passkey check. Data: \(data.base64EncodedString())")
        self.writeQ(data)
    }
    
    /// Used after entering PIN codes (only for DanaRS v3)
    public func finishV3Pairing(_ pairingKey: Data, _ randomPairingKey: Data) {
//        log.info("Storing security keys: Pairing key: \(pairingKey.base64EncodedString()), random pairing key: \(randomPairingKey.base64EncodedString())")
        
        DanaRSEncryption.setPairingKeys(pairingKey: pairingKey, randomPairingKey: randomPairingKey, randomSyncKey: nil)
        self.pumpManager.state.pairingKey = pairingKey
        self.pumpManager.state.randomPairingKey = randomPairingKey
        
        self.sendV3PairingInformation(0)
    }
    
    private func processEasyMenuCheck(_ data: Data) {
        if (DanaRSEncryption.enhancedEncryption == EncryptionType.RSv3.rawValue) {
            self.sendV3PairingInformationEmpty()
        } else {
            self.sendTimeInfo()
        }
    }
    
    private func processPairingRequest(_ data: Data) {
        if (data[2] == 0x00) {
            // Everything is order. Waiting for pump to send OPCODE_ENCRYPTION__PASSKEY_RETURN
            return
        }
        
        log.error("Passkey request failed. Data: \(data.base64EncodedString())")
        connectionFailure(NSError(domain: "Passkey request failed", code: 0, userInfo: nil))
    }
    
    private func processPairingRequest2(_ data: Data) {
        self.sendTimeInfo()
        
        let pairingKey = data.subdata(in: 2..<4)
        DanaRSEncryption.setPairingKeys(pairingKey: pairingKey, randomPairingKey: Data(), randomSyncKey: 0)
    }
    
    private func processConnectResponse(_ data: Data) {
        if (data.count == 4 && self.isOk(data)) {
            // response OK v1
            self.log.info("Setting encryption mode to DEFAULT")
            DanaRSEncryption.setEnhancedEncryption(EncryptionType.DEFAULT.rawValue)
            
            self.pumpManager.state.ignorePassword = false;
            
            let (pairingKey, _) = DanaRSEncryption.getPairingKeys()
            if (pairingKey.count > 0) {
                self.sendPassKeyCheck(pairingKey)
            } else {
                self.sendPairingRequest()
            }
        } else if (data.count == 9 && self.isOk(data)) {
            // response OK v3, 2nd layer encryption
            log.info("Setting encryption mode to RSv3")
            DanaRSEncryption.setEnhancedEncryption(EncryptionType.RSv3.rawValue)
            
            self.pumpManager.state.ignorePassword = true;
            
            self.pumpManager.state.hwModel = data[5]
            self.pumpManager.state.pumpProtocol = data[7]
            
            // Grab syncKey
            self.pumpManager.state.randomSyncKey = data[data.count - 1]
            
            if (self.pumpManager.state.hwModel == 0x05) {
                self.sendV3PairingInformationEmpty()
            } else if (self.pumpManager.state.hwModel == 0x06) {
                self.sendEasyMenuCheck()
            } else {
                log.error("Got invalid hwModel \(self.pumpManager.state.hwModel)")
                connectionFailure(NSError(domain: "Invalid hwModel", code: 0, userInfo: nil))
            }
        } else if (data.count == 14 && self.isOk(data)) {
            log.info("Setting encryption mode to BLE5")
            DanaRSEncryption.setEnhancedEncryption(EncryptionType.BLE_5.rawValue)
            
            self.pumpManager.state.hwModel = data[5]
            self.pumpManager.state.pumpProtocol = data[7]
            
            guard (self.pumpManager.state.hwModel == 0x09 || self.pumpManager.state.hwModel == 0x0a) else {
                log.error("Got invalid hwModel \(self.pumpManager.state.hwModel)")
                connectionFailure(NSError(domain: "Invalid hwModel", code: 0, userInfo: nil))
                return
            }
            
            var ble5Keys = data.subdata(in: 8..<14)
            if ble5Keys.filter({ $0 == 0 }).count != 0 {
                // Try to get keys from previous session
                ble5Keys = self.pumpManager.state.ble5Keys
            }
            
            guard ble5Keys.filter({ $0 == 0 }).count == 0 else {
                log.error("Invalid BLE-5 keys. Please unbound device and try again.")
                
                self.bluetoothManager.manager.cancelPeripheralConnection(self.connectedDevice)
                guard let completion = self.completion else {
                    return
                }
                
                completion(.invalidBle5Keys)
                return
            }
            
            DanaRSEncryption.setBle5Key(ble5Key: ble5Keys)
            self.pumpManager.state.ble5Keys = ble5Keys
            self.sendBLE5PairingInformation()
        } else if (data.count == 6 && self.isPump(data)) {
            log.error("PUMP_CHECK error. Data: \(data.base64EncodedString())")
            connectionFailure(NSError(domain: "PUMP_CHECK error", code: 0, userInfo: nil))
        } else if (data.count == 6 && isBusy(data)) {
            log.error("PUMP_CHECK_BUSY error. Data: \(data.base64EncodedString())")
            connectionFailure(NSError(domain: "PUMP_CHECK_BUSY error", code: 0, userInfo: nil))
        } else {
            log.error("PUMP_CHECK error, wrong serial number. Data: \(data.base64EncodedString())")
            connectionFailure(NSError(domain: "PUMP_CHECK error, wrong serial number", code: 0, userInfo: nil))
        }
    }
    
    private func processEncryptionResponse(_ data: Data) {
        if (DanaRSEncryption.enhancedEncryption == EncryptionType.BLE_5.rawValue) {
            self.finishConnection()
            
        } else if (DanaRSEncryption.enhancedEncryption == EncryptionType.RSv3.rawValue) {
            // data[2] : 0x00 OK  0x01 Error, No pairing
            if (data[2] == 0x00) {
                let (pairingKey, randomPairingKey) = DanaRSEncryption.getPairingKeys()
                if (pairingKey.count == 0 || randomPairingKey.count == 0) {
//                    log.info("Device is requesting pincode")
                    self.promptPincode(nil)
                    return
                }
                
                self.finishConnection()
            } else {
                self.sendV3PairingInformation(1)
            }
        } else {
            let highByte = UInt16((data[data.count - 1] & 0xff) << 8)
            let lowByte = UInt16(data[data.count - 2] & 0xff)
            let password = (highByte + lowByte) ^ 0x0d87
            if (password != self.pumpManager.state.devicePassword && !self.pumpManager.state.ignorePassword) {
                log.error("Invalid password")
                connectionFailure(NSError(domain: "Invalid password", code: 0, userInfo: nil))
                return
            }
            
            self.finishConnection()
        }
    }
    
    private func finishConnection() {
        self.pumpManager.state.isConnected = true
        log.info("Connection and encryption successful!")
        
        DispatchQueue.main.async {
            self.completion?(.success)
            self.completion = nil
        }
    }
    
    private func promptPincode(_ errorMessage: String?) {
        guard let completion = self.completion else {
            return
        }
        
        completion(.requestedPincode(errorMessage))
    }
    
    private func isOk(_ data: Data) -> Bool {
        return data[2] == okCharCodes[0] && data[3] == okCharCodes[1]
    }
    
    private func isPump(_ data: Data) -> Bool {
        return data[2] == pumpCharCodes[0] && data[3] == pumpCharCodes[1] && data[4] == pumpCharCodes[2] && data[5] == pumpCharCodes[3]
    }
    
    private func isBusy(_ data: Data) -> Bool {
        return data[2] == busyCharCodes[0] && data[3] == busyCharCodes[1] && data[4] == busyCharCodes[2] && data[5] == busyCharCodes[3]
    }
}

// MARK: Parsers for incomming messages
extension PeripheralManager {
    private func parseReceivedValue(_ receievedData: Data) {
        var data = receievedData
        
        if (data.count > 0 && self.pumpManager.state.isConnected && DanaRSEncryption.enhancedEncryption != EncryptionType.DEFAULT.rawValue) {
//            self.log.info("Second lvl decryption")
            data = DanaRSEncryption.decodeSecondLevel(data: data)
        }
        
        self.readBuffer.append(data)
        guard self.readBuffer.count >= 6 else {
            // Buffer is not ready to be processed
//            self.log.warning("Buffer not ready yet: \(self.readBuffer.base64EncodedString())")
            return
        }
        
        if (
            !(self.readBuffer[0] == self.PACKET_START_BYTE || self.readBuffer[0] == self.ENCRYPTED_START_BYTE) ||
            !(self.readBuffer[1] == self.PACKET_START_BYTE || self.readBuffer[1] == self.ENCRYPTED_START_BYTE)
        ) {
            // The buffer does not start with the opening bytes. Check if the buffer is filled with old data
            if let indexStartByte = self.readBuffer.firstIndex(of: self.PACKET_START_BYTE) {
                self.readBuffer = self.readBuffer.subdata(in: indexStartByte..<self.readBuffer.count)
            } else if let indexEncryptedStartByte = self.readBuffer.firstIndex(of: self.ENCRYPTED_START_BYTE) {
                self.readBuffer = self.readBuffer.subdata(in: indexEncryptedStartByte..<self.readBuffer.count)
            } else {
                log.error("Received invalid packets. Starting bytes do not exists in message. Encryption mode possibly wrong Data: \(self.readBuffer.base64EncodedString())")
                self.readBuffer = Data([])
                self.bluetoothManager.manager.cancelPeripheralConnection(self.connectedDevice)
                return
            }
        }
        
        let length = Int(self.readBuffer[2])
        guard (length + 7 == self.readBuffer.count) else {
            // Not all packets have been received yet...
//            self.log.warning("Not all packets have been received yet - Should be: \(length + 7), currently: \(self.readBuffer.count)")
            return
        }
        
        guard (
            (self.readBuffer[length + 5] == self.PACKET_END_BYTE || self.readBuffer[length + 5] == self.ENCRYPTED_END_BYTE) &&
            (self.readBuffer[length + 6] == self.PACKET_END_BYTE || self.readBuffer[length + 6] == self.ENCRYPTED_END_BYTE)
          ) else {
            // Invalid packets received...
            log.error("Received invalid packets. Ending bytes do not match. Data: \(self.readBuffer.base64EncodedString())")
            self.readBuffer = Data([])
            return
          }
        
//        log.info("Received message! Starting to decrypt data: \(self.readBuffer.base64EncodedString())")
        let decryptedData = DanaRSEncryption.decodePacket(buffer: self.readBuffer, deviceName: self.deviceName)
        self.readBuffer = Data([])
        
        guard decryptedData.count > 0 else {
            log.error("Decryption failed...")
            return
        }
        
//        log.info("Decoding successful! Data: \(decryptedData.base64EncodedString())")
        if (decryptedData[0] == DanaPacketType.TYPE_ENCRYPTION_RESPONSE) {
            switch(decryptedData[1]) {
            case DanaPacketType.OPCODE_ENCRYPTION__PUMP_CHECK:
                self.processConnectResponse(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__TIME_INFORMATION:
                self.processEncryptionResponse(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__CHECK_PASSKEY:
                if (decryptedData[2] == 0x05) {
                    self.sendTimeInfo()
                } else {
                    self.sendPairingRequest()
                }
                return
            case DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_REQUEST:
                self.processPairingRequest(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__PASSKEY_RETURN:
                self.processPairingRequest2(decryptedData)
                return
            case DanaPacketType.OPCODE_ENCRYPTION__GET_PUMP_CHECK:
                if (decryptedData[2] == 0x05) {
                    self.sendTimeInfo()
                } else {
                    self.sendEasyMenuCheck()
                }
                return
            case DanaPacketType.OPCODE_ENCRYPTION__GET_EASYMENU_CHECK:
                self.processEasyMenuCheck(decryptedData)
                return
            default:
                log.error("Received invalid encryption command type \(decryptedData[1])")
                return
            }
        }
        
        guard(decryptedData[0] == DanaPacketType.TYPE_RESPONSE || decryptedData[0] == DanaPacketType.TYPE_NOTIFY) else {
            log.error("Received invalid packet type \(decryptedData[0])")
            return
        }
        
        self.processMessage(decryptedData)
    }
    
    private func processMessage(_ data: Data) {
        let message = parseMessage(data: data, usingUtc: self.pumpManager.state.usingUtc)
        guard let message = message else {
            log.error("Received unparsable message. Data: \(data.base64EncodedString())")
            return
        }
        
        if (message.notifyType != nil) {
            switch message.notifyType {
            case CommandNotifyDeliveryComplete:
                let data = message.data as! PacketNotifyDeliveryComplete
                self.pumpManager.notifyBolusDone(deliveredUnits: data.deliveredInsulin)
                return
            case CommandNotifyDeliveryRateDisplay:
                let data = message.data as! PacketNotifyDeliveryRateDisplay
                self.pumpManager.notifyBolusDidUpdate(deliveredUnits: data.deliveredInsulin)
                return
            case CommandNotifyAlarm:
                let data = message.data as! PacketNotifyAlarm
                self.pumpManager.notifyBolusError()
                self.pumpManager.notifyAlert(data.alert)
                return
            default:
                self.pumpManager.notifyBolusError()
                return
            }
        }
        
        // Message received and dequeueing timeout
        guard let opCode = message.opCode, let continuation = self.writeQueue[opCode] else {
            log.error("No continuation token found to send this message back...")
            self.writeSemaphore.signal()
            return
        }
        
        if let data = message.data as? HistoryItem {
            if data.code == HistoryCode.RECORD_TYPE_DONE_UPLOAD {
                continuation.resume(returning: DanaParsePacket<[HistoryItem]>(success: true, rawData: Data([]), data: self.historyLog.map({ $0 })))
                
                self.writeQueue[opCode] = nil
                self.writeTimeoutTask?.cancel()
                self.writeTimeoutTask = nil
                self.historyLog = []
                self.writeSemaphore.signal()
            } else {
                self.historyLog.append(data)
            }

            return
        }
        
        continuation.resume(returning: message)
        
        self.writeQueue[opCode] = nil
        self.writeTimeoutTask?.cancel()
        self.writeTimeoutTask = nil
        self.writeSemaphore.signal()
    }
    
    private func isHistoryPacket(opCode: UInt16) -> Bool {
        return opCode > CommandHistoryBolus && opCode < CommandHistoryAll
    }
}
