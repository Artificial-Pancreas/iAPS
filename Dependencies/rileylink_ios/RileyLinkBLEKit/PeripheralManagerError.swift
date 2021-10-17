//
//  PeripheralManagerError.swift
//  RileyLinkBLEKit
//
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import CoreBluetooth


public enum PeripheralManagerError: Error {
    case cbPeripheralError(Error)
    case notReady
    case timeout
    case unknownCharacteristic
}


extension PeripheralManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cbPeripheralError(let error):
            return error.localizedDescription
        case .notReady:
            return LocalizedString("RileyLink is not connected", comment: "Not ready error description")
        case .timeout:
            return LocalizedString("RileyLink did not respond in time", comment: "Timeout error description")
        case .unknownCharacteristic:
            return LocalizedString("Unknown characteristic", comment: "Error description")
        }
    }

    public var failureReason: String? {
        switch self {
        case .cbPeripheralError(let error as NSError):
            return error.localizedFailureReason
        case .unknownCharacteristic:
            return LocalizedString("The RileyLink was temporarily disconnected", comment: "Failure reason: unknown peripheral characteristic")
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .cbPeripheralError(let error as NSError):
            return error.localizedRecoverySuggestion
        case .unknownCharacteristic:
            return LocalizedString("Make sure the device is nearby, and the issue should resolve automatically", comment: "Recovery suggestion for unknown peripheral characteristic")
        default:
            return nil
        }
    }
}
