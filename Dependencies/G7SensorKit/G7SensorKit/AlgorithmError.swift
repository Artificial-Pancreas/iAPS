//
//  AlgorithmError.swift
//  G7SensorKit
//
//  Created by Pete Schwamb on 11/11/22.
//

import Foundation

enum AlgorithmError: Error {
    case unreliableState(AlgorithmState)
}

extension AlgorithmError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreliableState:
            return LocalizedString("Glucose data is unavailable", comment: "Error description for unreliable state")
        }
    }

    var failureReason: String? {
        switch self {
        case .unreliableState(let state):
            return state.localizedDescription
        }
    }
}


extension AlgorithmState {
    public var localizedDescription: String {
        switch self {
        case .known(let state):
            switch state {
            case .ok:
                return LocalizedString("Sensor is OK", comment: "The description of sensor algorithm state when sensor is ok.")
            case .stopped:
                return LocalizedString("Sensor is stopped", comment: "The description of sensor algorithm state when sensor is stopped.")
            case .warmup, .questionMarks:
                return LocalizedString("Sensor is warming up", comment: "The description of sensor algorithm state when sensor is warming up.")
            case .expired:
                return LocalizedString("Sensor expired", comment: "The description of sensor algorithm state when sensor is expired.")
            case .sensorFailed:
                return LocalizedString("Sensor failed", comment: "The description of sensor algorithm state when sensor failed.")
            }
        case .unknown(let rawValue):
            return String(format: LocalizedString("Sensor is in unknown state %1$d", comment: "The description of sensor algorithm state when raw value is unknown. (1: missing data details)"), rawValue)
        }
    }
}
