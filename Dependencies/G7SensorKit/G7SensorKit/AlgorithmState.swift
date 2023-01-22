//
//  CalibrationState.swift
//  xDripG5
//
//  Created by Nate Racklyeft on 8/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public enum AlgorithmState: RawRepresentable {
    public typealias RawValue = UInt8

    public enum State: RawValue {
        case stopped = 1
        case warmup = 2
        case ok = 6
        case questionMarks = 18
        case expired = 24
        case sensorFailed = 25
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

    public var sensorFailed: Bool {
        guard case .known(let state) = self else {
            return false
        }

        switch state {
        case .sensorFailed:
            return true
        default:
            return false
        }
    }

    public var isInWarmup: Bool {
        guard case .known(let state) = self else {
            return false
        }

        switch state {
        case .warmup:
            return true
        default:
            return false
        }
    }

    public var isInSensorError: Bool {
        guard case .known(let state) = self else {
            return false
        }

        switch state {
        case .questionMarks:
            return true
        default:
            return false
        }
    }


    public var hasReliableGlucose: Bool {
        guard case .known(let state) = self else {
            return false
        }

        switch state {
        case .stopped,
             .warmup,
             .questionMarks,
             .expired,
             .sensorFailed:
            return false
        case .ok:
            return true
        }
    }
}

extension AlgorithmState: Equatable {
    public static func ==(lhs: AlgorithmState, rhs: AlgorithmState) -> Bool {
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

extension AlgorithmState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .known(let state):
            return String(describing: state)
        case .unknown(let value):
            return ".unknown(\(value))"
        }
    }
}
