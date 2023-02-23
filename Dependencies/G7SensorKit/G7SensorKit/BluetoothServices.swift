//
//  BluetoothServices.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 10/16/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import CoreBluetooth

protocol CBUUIDRawValue: RawRepresentable {}
extension CBUUIDRawValue where RawValue == String {
    var cbUUID: CBUUID {
        return CBUUID(string: rawValue)
    }
}


enum SensorServiceUUID: String, CBUUIDRawValue {
    case deviceInfo = "180A"
    case advertisement = "FEBC"
    case cgmService = "F8083532-849E-531C-C594-30F1F86A4EA5"

    case serviceB = "F8084532-849E-531C-C594-30F1F86A4EA5"
}


enum DeviceInfoCharacteristicUUID: String, CBUUIDRawValue {
    // Read
    // "DexcomUN"
    case manufacturerNameString = "2A29"
}


enum CGMServiceCharacteristicUUID: String, CBUUIDRawValue {

    // Read/Notify
    case communication = "F8083533-849E-531C-C594-30F1F86A4EA5"

    // Write/Indicate
    case control = "F8083534-849E-531C-C594-30F1F86A4EA5"

    // Write/Indicate
    case authentication = "F8083535-849E-531C-C594-30F1F86A4EA5"

    // Read/Write/Notify
    case backfill = "F8083536-849E-531C-C594-30F1F86A4EA5"
}


enum ServiceBCharacteristicUUID: String, CBUUIDRawValue {
    // Write/Indicate
    case characteristicE = "F8084533-849E-531C-C594-30F1F86A4EA5"
    // Read/Write/Notify
    case characteristicF = "F8084534-849E-531C-C594-30F1F86A4EA5"
}


extension G7PeripheralManager.Configuration {
    static var dexcomG7: G7PeripheralManager.Configuration {
        return G7PeripheralManager.Configuration(
            serviceCharacteristics: [
                SensorServiceUUID.cgmService.cbUUID: [
                    //CGMServiceCharacteristicUUID.communication.cbUUID, // Unused for now
                    CGMServiceCharacteristicUUID.authentication.cbUUID,
                    CGMServiceCharacteristicUUID.control.cbUUID,
                    CGMServiceCharacteristicUUID.backfill.cbUUID,
                ]
            ],
            notifyingCharacteristics: [:],
            valueUpdateMacros: [:]
        )
    }
}
