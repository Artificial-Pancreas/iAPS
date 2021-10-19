//
//  CalibrationState.swift
//  xDripG5
//
//  Created by Nate Racklyeft on 8/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum CalibrationState: RawRepresentable {
    public typealias RawValue = UInt8

    public enum State: RawValue {
        case stopped = 1
        case warmup = 2

        case needFirstInitialCalibration = 4
        case needSecondInitialCalibration = 5
        case ok = 6
        case needCalibration7 = 7
        case calibrationError8 = 8
        case calibrationError9 = 9
        case calibrationError10 = 10
        case sensorFailure11 = 11
        case sensorFailure12 = 12
        case calibrationError13 = 13
        case needCalibration14 = 14
        case sessionFailure15 = 15
        case sessionFailure16 = 16
        case sessionFailure17 = 17
        case questionMarks = 18
    }

    case known(State)
    case unknown(RawValue)

    public init(rawValue: RawValue) {
        guard let state = State(rawValue: rawValue) else {
            self = .unknown(rawValue)
            return
        }

        self = .known(state)
    }

    public var rawValue: RawValue {
        switch self {
        case .known(let state):
            return state.rawValue
        case .unknown(let rawValue):
            return rawValue
        }
    }

    public var hasReliableGlucose: Bool {
        guard case .known(let state) = self else {
            return false
        }

        switch state {
        case .stopped,
             .warmup,
             .needFirstInitialCalibration,
             .needSecondInitialCalibration,
             .calibrationError8,
             .calibrationError9,
             .calibrationError10,
             .sensorFailure11,
             .sensorFailure12,
             .calibrationError13,
             .sessionFailure15,
             .sessionFailure16,
             .sessionFailure17,
             .questionMarks:
            return false
        case .ok, .needCalibration7, .needCalibration14:
            return true
        }
    }
}

extension CalibrationState: Equatable {
    public static func ==(lhs: CalibrationState, rhs: CalibrationState) -> Bool {
        switch (lhs, rhs) {
        case (.known(let lhs), .known(let rhs)):
            return lhs == rhs
        case (.unknown(let lhs), .unknown(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

extension CalibrationState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .known(let state):
            return String(describing: state)
        case .unknown(let value):
            return ".unknown(\(value))"
        }
    }
}
