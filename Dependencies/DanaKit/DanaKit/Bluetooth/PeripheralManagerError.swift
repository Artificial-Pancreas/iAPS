//
//  PeripheralManagerErrors.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/18/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

enum PeripheralManagerError: Error {
    case cbPeripheralError(Error)
    case notReady
    case incorrectResponse
    case timeout([PeripheralManager.CommandCondition])
    case emptyValue
    case unknownCharacteristic
    case nack
}

extension PeripheralManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cbPeripheralError(let error):
            return error.localizedDescription
        case .notReady:
            return LocalizedString("Peripheral Not Ready", comment: "Error message description for PeripheralManagerError.notReady")
        case .incorrectResponse:
            return LocalizedString("Incorrect Response", comment: "Error message description for PeripheralManagerError.incorrectResponse")
        case .timeout:
            return LocalizedString("Timeout", comment: "Error message description for PeripheralManagerError.timeout")
        case .emptyValue:
            return LocalizedString("Empty Value", comment: "Error message description for PeripheralManagerError.emptyValue")
        case .unknownCharacteristic:
            return LocalizedString("Unknown Characteristic", comment: "Error message description for PeripheralManagerError.unknownCharacteristic")
        case .nack:
            return LocalizedString("Nack", comment: "Error message description for PeripheralManagerError.nack")
        }
    }
}
