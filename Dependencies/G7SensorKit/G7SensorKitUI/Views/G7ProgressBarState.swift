//
//  G7ProgressBarState.swift
//  G7SensorKitUI
//
//  Created by Pete Schwamb on 11/22/22.
//

import Foundation

enum G7ProgressBarState {
    case warmupProgress
    case lifetimeRemaining
    case gracePeriodRemaining
    case sensorFailed
    case sensorExpired
    case searchingForSensor

    var label: String {
        switch self {
        case .searchingForSensor:
            return LocalizedString("Searching for sensor", comment: "G7 Progress bar label when searching for sensor")
        case .sensorExpired:
            return LocalizedString("Sensor expired", comment: "G7 Progress bar label when sensor expired")
        case .warmupProgress:
            return LocalizedString("Warmup completes", comment: "G7 Progress bar label when sensor in warmup")
        case .sensorFailed:
            return LocalizedString("Sensor failed", comment: "G7 Progress bar label when sensor failed")
        case .lifetimeRemaining:
            return LocalizedString("Sensor expires", comment: "G7 Progress bar label when sensor lifetime progress showing")
        case .gracePeriodRemaining:
            return LocalizedString("Grace period remaining", comment: "G7 Progress bar label when sensor grace period progress showing")
        }
    }

    var labelColor: ColorStyle {
        switch self {
        case .sensorExpired:
            return .critical
        default:
            return .normal
        }
    }
}
