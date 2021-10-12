//
//  PeripheralManager+G5.swift
//  xDripG5
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import CoreBluetooth
import os.log


private let log = OSLog(category: "PeripheralManager+G5")


extension PeripheralManager {
    private func getCharacteristicWithUUID(_ uuid: CGMServiceCharacteristicUUID) -> CBCharacteristic? {
        return peripheral.getCharacteristicWithUUID(uuid)
    }

    func setNotifyValue(_ enabled: Bool,
        for characteristicUUID: CGMServiceCharacteristicUUID,
        timeout: TimeInterval = 2) throws
    {
        guard let characteristic = getCharacteristicWithUUID(characteristicUUID) else {
            throw PeripheralManagerError.unknownCharacteristic
        }

        try setNotifyValue(enabled, for: characteristic, timeout: timeout)
    }

    func readMessage<R: TransmitterRxMessage>(
        for characteristicUUID: CGMServiceCharacteristicUUID,
        timeout: TimeInterval = 2
    ) throws -> R
    {
        guard let characteristic = getCharacteristicWithUUID(characteristicUUID) else {
            throw PeripheralManagerError.unknownCharacteristic
        }

        var capturedResponse: R?

        try runCommand(timeout: timeout) {
            addCondition(.valueUpdate(characteristic: characteristic, matching: { (data) -> Bool in
                guard let value = data else {
                    return false
                }

                guard let response = R(data: value) else {
                    // We don't recognize the contents. Keep listening.
                    return false
                }

                capturedResponse = response
                return true
            }))

            peripheral.readValue(for: characteristic)
        }

        guard let response = capturedResponse else {
            // TODO: This is an "unknown value" issue, not a timeout
            if let value = characteristic.value {
                log.error("Unknown response data: %{public}@", value.hexadecimalString)
            }
            throw PeripheralManagerError.timeout
        }

        return response
    }

    /// - Throws: PeripheralManagerError
    func writeMessage<T: RespondableMessage>(_ message: T,
        for characteristicUUID: CGMServiceCharacteristicUUID,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval = 2
    ) throws -> T.Response
    {
        guard let characteristic = getCharacteristicWithUUID(characteristicUUID) else {
            throw PeripheralManagerError.unknownCharacteristic
        }

        var capturedResponse: T.Response?

        try runCommand(timeout: timeout) {
            if case .withResponse = type {
                addCondition(.write(characteristic: characteristic))
            }

            if characteristic.isNotifying {
                addCondition(.valueUpdate(characteristic: characteristic, matching: { (data) -> Bool in
                    guard let value = data else {
                        return false
                    }

                    guard let response = T.Response(data: value) else {
                        // We don't recognize the contents. Keep listening.
                        return false
                    }

                    capturedResponse = response
                    return true
                }))
            }

            peripheral.writeValue(message.data, for: characteristic, type: type)
        }

        guard let response = capturedResponse else {
            // TODO: This is an "unknown value" issue, not a timeout
            if let value = characteristic.value {
                log.error("Unknown response data: %{public}@", value.hexadecimalString)
            }
            throw PeripheralManagerError.timeout
        }

        return response
    }

    /// - Throws: PeripheralManagerError
    func writeMessage(_ message: TransmitterTxMessage,
        for characteristicUUID: CGMServiceCharacteristicUUID,
        type: CBCharacteristicWriteType = .withResponse,
        timeout: TimeInterval = 2) throws
    {
        guard let characteristic = getCharacteristicWithUUID(characteristicUUID) else {
            throw PeripheralManagerError.unknownCharacteristic
        }

        try writeValue(message.data, for: characteristic, type: type, timeout: timeout)
    }
}


fileprivate extension CBPeripheral {
    func getServiceWithUUID(_ uuid: TransmitterServiceUUID) -> CBService? {
        return services?.itemWithUUIDString(uuid.rawValue)
    }

    func getCharacteristicForServiceUUID(_ serviceUUID: TransmitterServiceUUID, withUUIDString UUIDString: String) -> CBCharacteristic? {
        guard let characteristics = getServiceWithUUID(serviceUUID)?.characteristics else {
            return nil
        }

        return characteristics.itemWithUUIDString(UUIDString)
    }

    func getCharacteristicWithUUID(_ uuid: CGMServiceCharacteristicUUID) -> CBCharacteristic? {
        return getCharacteristicForServiceUUID(.cgmService, withUUIDString: uuid.rawValue)
    }
}
