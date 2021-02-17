//
//  PeripheralManager+RileyLink.swift
//  xDripG5
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import os.log


protocol CBUUIDRawValue: RawRepresentable {}
extension CBUUIDRawValue where RawValue == String {
    var cbUUID: CBUUID {
        return CBUUID(string: rawValue)
    }
}


enum RileyLinkServiceUUID: String, CBUUIDRawValue {
    case main = "0235733B-99C5-4197-B856-69219C2A3845"
}

enum MainServiceCharacteristicUUID: String, CBUUIDRawValue {
    case data            = "C842E849-5028-42E2-867C-016ADADA9155"
    case responseCount   = "6E6C7910-B89E-43A5-A0FE-50C5E2B81F4A"
    case customName      = "D93B2AF0-1E28-11E4-8C21-0800200C9A66"
    case timerTick       = "6E6C7910-B89E-43A5-78AF-50C5E2B86F7E"
    case firmwareVersion = "30D99DC9-7C91-4295-A051-0A104D238CF2"
    case ledMode         = "C6D84241-F1A7-4F9C-A25F-FCE16732F14E"
}

enum RileyLinkLEDMode: UInt8 {
    case off  = 0x00
    case on   = 0x01
    case auto = 0x02
}


extension PeripheralManager.Configuration {
    static var rileyLink: PeripheralManager.Configuration {
        return PeripheralManager.Configuration(
            serviceCharacteristics: [
                RileyLinkServiceUUID.main.cbUUID: [
                    MainServiceCharacteristicUUID.data.cbUUID,
                    MainServiceCharacteristicUUID.responseCount.cbUUID,
                    MainServiceCharacteristicUUID.customName.cbUUID,
                    MainServiceCharacteristicUUID.timerTick.cbUUID,
                    MainServiceCharacteristicUUID.firmwareVersion.cbUUID,
                    MainServiceCharacteristicUUID.ledMode.cbUUID
                ]
            ],
            notifyingCharacteristics: [
                RileyLinkServiceUUID.main.cbUUID: [
                    MainServiceCharacteristicUUID.responseCount.cbUUID
                    // TODO: Should timer tick default to on?
                ]
            ],
            valueUpdateMacros: [
                // When the responseCount changes, the data characteristic should be read.
                MainServiceCharacteristicUUID.responseCount.cbUUID: { (manager: PeripheralManager) in
                    guard let dataCharacteristic = manager.peripheral.getCharacteristicWithUUID(.data)
                    else {
                        return
                    }

                    manager.peripheral.readValue(for: dataCharacteristic)
                }
            ]
        )
    }
}


fileprivate extension CBPeripheral {
    func getCharacteristicWithUUID(_ uuid: MainServiceCharacteristicUUID, serviceUUID: RileyLinkServiceUUID = .main) -> CBCharacteristic? {
        guard let service = services?.itemWithUUID(serviceUUID.cbUUID) else {
            return nil
        }

        return service.characteristics?.itemWithUUID(uuid.cbUUID)
    }
}


extension CBCentralManager {
    func scanForPeripherals(withOptions options: [String: Any]? = nil) {
        scanForPeripherals(withServices: [RileyLinkServiceUUID.main.cbUUID], options: options)
    }
}


extension Command {
    /// Encodes a command's data by validating and prepending its length
    ///
    /// - Returns: Writable command data
    /// - Throws: RileyLinkDeviceError.writeSizeLimitExceeded if the command data is too long
    fileprivate func writableData() throws -> Data {
        var data = self.data

        guard data.count <= 220 else {
            throw RileyLinkDeviceError.writeSizeLimitExceeded(maxLength: 220)
        }

        data.insert(UInt8(clamping: data.count), at: 0)
        return data
    }
}


private let log = OSLog(category: "PeripheralManager+RileyLink")


extension PeripheralManager {
    static let expectedMaxBLELatency: TimeInterval = 2

    var timerTickEnabled: Bool {
        return peripheral.getCharacteristicWithUUID(.timerTick)?.isNotifying ?? false
    }

    func setTimerTickEnabled(_ enabled: Bool, timeout: TimeInterval = expectedMaxBLELatency, completion: ((_ error: RileyLinkDeviceError?) -> Void)? = nil) {
        perform { (manager) in
            do {
                guard let characteristic = manager.peripheral.getCharacteristicWithUUID(.timerTick) else {
                    throw PeripheralManagerError.unknownCharacteristic
                }

                try manager.setNotifyValue(enabled, for: characteristic, timeout: timeout)
                completion?(nil)
            } catch let error as PeripheralManagerError {
                completion?(.peripheralManagerError(error))
            } catch {
                assertionFailure()
            }
        }
    }

    func setLEDMode(mode: RileyLinkLEDMode) {
        perform { (manager) in
            do {
                guard let characteristic = manager.peripheral.getCharacteristicWithUUID(.ledMode) else {
                    throw PeripheralManagerError.unknownCharacteristic
                }
                let value = Data([mode.rawValue])
                try manager.writeValue(value, for: characteristic, type: .withResponse, timeout: PeripheralManager.expectedMaxBLELatency)
            } catch (let error) {
                assertionFailure(String(describing: error))
            }
        }
    }

    

    func startIdleListening(idleTimeout: TimeInterval, channel: UInt8, timeout: TimeInterval = expectedMaxBLELatency, completion: @escaping (_ error: RileyLinkDeviceError?) -> Void) {
        perform { (manager) in
            let command = GetPacket(listenChannel: channel, timeoutMS: UInt32(clamping: Int(idleTimeout.milliseconds)))

            do {
                try manager.writeCommandWithoutResponse(command, timeout: timeout)
                completion(nil)
            } catch let error as RileyLinkDeviceError {
                completion(error)
            } catch {
                assertionFailure()
            }
        }
    }

    func setCustomName(_ name: String, timeout: TimeInterval = expectedMaxBLELatency, completion: ((_ error: RileyLinkDeviceError?) -> Void)? = nil) {
        guard let value = name.data(using: .utf8) else {
            completion?(.invalidInput(name))
            return
        }

        perform { (manager) in
            do {
                guard let characteristic = manager.peripheral.getCharacteristicWithUUID(.customName) else {
                    throw PeripheralManagerError.unknownCharacteristic
                }

                try manager.writeValue(value, for: characteristic, type: .withResponse, timeout: timeout)
                completion?(nil)
            } catch let error as PeripheralManagerError {
                completion?(.peripheralManagerError(error))
            } catch {
                assertionFailure()
            }
        }
    }
}



// MARK: - Synchronous commands
extension PeripheralManager {
    enum ResponseType {
        case single
        case buffered
    }

    /// Invokes a command expecting a response
    ///
    /// - Parameters:
    ///   - command: The command
    ///   - timeout: The amount of time to wait for the peripheral to respond before throwing a timeout error
    ///   - responseType: The BLE response value framing method
    /// - Returns: The received response
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    ///     - RileyLinkDeviceError.writeSizeLimitExceeded
    func writeCommand<C: Command>(_ command: C, timeout: TimeInterval, responseType: ResponseType) throws -> C.ResponseType {
        guard let characteristic = peripheral.getCharacteristicWithUUID(.data) else {
            throw RileyLinkDeviceError.peripheralManagerError(.unknownCharacteristic)
        }

        let value = try command.writableData()


        switch responseType {
        case .single:
            log.debug("RL Send (single): %@", value.hexadecimalString)
            return try writeCommand(value,
                for: characteristic,
                timeout: timeout
            )
        case .buffered:
            log.debug("RL Send (buffered): %@", value.hexadecimalString)
            return try writeLegacyCommand(value,
                for: characteristic,
                timeout: timeout,
                endOfResponseMarker: 0x00
            )
        }
    }

    /// Invokes a command without waiting for its response
    ///
    /// - Parameters:
    ///   - command: The command
    ///   - timeout: The amount of time to wait for the peripheral to confirm the write before throwing a timeout error
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    ///     - RileyLinkDeviceError.writeSizeLimitExceeded
    fileprivate func writeCommandWithoutResponse<C: Command>(_ command: C, timeout: TimeInterval) throws {
        guard let characteristic = peripheral.getCharacteristicWithUUID(.data) else {
            throw RileyLinkDeviceError.peripheralManagerError(.unknownCharacteristic)
        }

        let value = try command.writableData()

        log.debug("RL Send (no response expected): %@", value.hexadecimalString)

        do {
            try writeValue(value, for: characteristic, type: .withResponse, timeout: timeout)
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }
    }
    
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    func readRadioFirmwareVersion(timeout: TimeInterval, responseType: ResponseType) throws -> String {
        let response = try writeCommand(GetVersion(), timeout: timeout, responseType: responseType)
        return response.version
    }

    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    func readBluetoothFirmwareVersion(timeout: TimeInterval) throws -> String {
        guard let characteristic = peripheral.getCharacteristicWithUUID(.firmwareVersion) else {
            throw RileyLinkDeviceError.peripheralManagerError(.unknownCharacteristic)
        }

        do {
            guard let data = try readValue(for: characteristic, timeout: timeout) else {
                // TODO: This is an "unknown value" issue, not a timeout
                throw RileyLinkDeviceError.peripheralManagerError(.timeout)
            }

            guard let version = String(bytes: data, encoding: .utf8) else {
                throw RileyLinkDeviceError.invalidResponse(data)
            }

            return version
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }
    }
}


// MARK: - Lower-level helper operations
extension PeripheralManager {

    /// Writes command data expecting a single response
    ///
    /// - Parameters:
    ///   - data: The command data
    ///   - characteristic: The peripheral characteristic to write
    ///   - type: The type of characteristic write
    ///   - timeout: The amount of time to wait for the peripheral to respond before throwing a timeout error
    /// - Returns: The recieved response
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    private func writeCommand<R: Response>(_ data: Data,
        for characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval
    ) throws -> R
    {
        var capturedResponse: R?

        do {
            try runCommand(timeout: timeout) {
                if case .withResponse = type {
                    addCondition(.write(characteristic: characteristic))
                }

                addCondition(.valueUpdate(characteristic: characteristic, matching: { value in
                    guard let value = value, value.count > 0 else {
                        log.debug("Empty response from RileyLink. Continuing to listen for command response.")
                        return false
                    }
                    
                    log.debug("RL Recv(single): %@", value.hexadecimalString)

                    guard let code = ResponseCode(rawValue: value[0]) else {
                        let unknownCode = value[0..<1].hexadecimalString
                        log.error("Unknown response code from RileyLink: %{public}@. Continuing to listen for command response.", unknownCode)
                        return false
                    }

                    switch code {
                    case .commandInterrupted:
                        // This is expected in cases where an "Idle" GetPacket command is running
                        log.debug("Idle command interrupted. Continuing to listen for command response.")
                        return false
                    default:
                        guard let response = R(data: value) else {
                            log.error("Unable to parse response.")
                            // We don't recognize the contents. Keep listening.
                            return false
                        }
                        log.debug("RileyLink response: %{public}@", String(describing: response))
                        capturedResponse = response
                        return true
                    }
                }))

                peripheral.writeValue(data, for: characteristic, type: type)
            }
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }

        guard let response = capturedResponse else {
            throw RileyLinkDeviceError.invalidResponse(characteristic.value ?? Data())
        }

        return response
    }

    /// Writes command data expecting a bufferred response
    ///
    /// - Parameters:
    ///   - data: The command data
    ///   - characteristic: The peripheral characteristic to write
    ///   - type: The type of characteristic write
    ///   - timeout: The amount of time to wait for the peripheral to respond before throwing a timeout error
    ///   - endOfResponseMarker: The marker delimiting the end of a response in the buffer
    /// - Returns: The received response. In the event of multiple responses in the buffer, the first parsable response is returned.
    /// - Throws:
    ///     - RileyLinkDeviceError.invalidResponse
    ///     - RileyLinkDeviceError.peripheralManagerError
    private func writeLegacyCommand<R: Response>(_ data: Data,
        for characteristic: CBCharacteristic,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval,
        endOfResponseMarker: UInt8
    ) throws -> R
    {
        var capturedResponse: R?
        var buffer = ResponseBuffer<R>(endMarker: endOfResponseMarker)

        do {
            try runCommand(timeout: timeout) {
                if case .withResponse = type {
                    addCondition(.write(characteristic: characteristic))
                }

                addCondition(.valueUpdate(characteristic: characteristic, matching: { value in
                    guard let value = value else {
                        return false
                    }

                    log.debug("RL Recv(buffered): %@", value.hexadecimalString)
                    buffer.append(value)

                    for response in buffer.responses {
                        switch response.code {
                        case .rxTimeout, .zeroData, .invalidParam, .unknownCommand:
                            log.debug("RileyLink response: %{public}@", String(describing: response))
                            capturedResponse = response
                            return true
                        case .commandInterrupted:
                            // This is expected in cases where an "Idle" GetPacket command is running
                            log.debug("RileyLink response: %{public}@", String(describing: response))
                        case .success:
                            capturedResponse = response
                            return true
                        }
                    }

                    return false
                }))

                peripheral.writeValue(data, for: characteristic, type: type)
            }
        } catch let error as PeripheralManagerError {
            throw RileyLinkDeviceError.peripheralManagerError(error)
        }

        guard let response = capturedResponse else {
            throw RileyLinkDeviceError.invalidResponse(characteristic.value ?? Data())
        }

        return response
    }
}
