//
//  TransmitterStatus.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 3/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum TransmitterStatus {
    public typealias RawValue = UInt8

    case ok
    case lowBattery
    case unknown(RawValue)

    init(rawValue: RawValue) {
        switch rawValue {
        case 0:
            self = .ok
        case 0x81:
            self = .lowBattery
        default:
            self = .unknown(rawValue)
        }
    }
}


extension TransmitterStatus: Equatable { }

public func ==(lhs: TransmitterStatus, rhs: TransmitterStatus) -> Bool {
    switch (lhs, rhs) {
    case (.ok, .ok), (.lowBattery, .lowBattery):
        return true
    case (.unknown(let left), .unknown(let right)) where left == right:
        return true
    default:
        return false
    }
}


extension TransmitterStatus {
    public var localizedDescription: String {
        switch self {
        case .ok:
            return LocalizedString("OK", comment: "Describes a functioning transmitter")
        case .lowBattery:
            return LocalizedString("Low Battery", comment: "Describes a low battery")
        case .unknown(let value):
            return "TransmitterStatus.unknown(\(value))"
        }
    }
}
