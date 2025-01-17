//
//  DanaKitErrors.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 09/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

public enum DanaKitPumpManagerError {
    case noConnection
    case pumpSuspended
    case pumpIsBusy
    case failedTempBasalAdjustment(_ extraMessage: String)
    case failedSuspensionAdjustment
    case failedBasalGeneration
    case failedBasalAdjustment
    case failedTimeAdjustment
    case unsupportedTempBasal(_ duration: TimeInterval)
    case bolusTimeoutActive
    case bolusMaxViolation
    case bolusInsulinLimitViolation
    case unknown(_ message: String)
}


extension DanaKitPumpManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noConnection:
            return LocalizedString("Failed to make a connection", comment: "Error description when no rileylink connected")
        case .failedTempBasalAdjustment(let reason):
            return LocalizedString("Failed to adjust temp basal. \(reason)", comment: "Error description when failed temp adjustment")
        case .failedSuspensionAdjustment:
            return LocalizedString("Failed to adjust suspension", comment: "Error description when failed suspension adjustment")
        case .failedBasalGeneration:
            return LocalizedString("Failed to generate Dana basal program", comment: "Error description when failed generating basal program")
        case .failedBasalAdjustment:
            return LocalizedString("Failed to adjust basal", comment: "Error description when failed basal adjustment")
        case .unsupportedTempBasal(let duration):
            return LocalizedString("Setting temp basal is not supported at this time. Duration: \(duration)sec", comment: "Error description when trying to set temp basal")
        case .pumpSuspended:
            return LocalizedString("The insulin delivery has been suspend. Action failed", comment: "Error description when pump is suspended")
        case .failedTimeAdjustment:
            return LocalizedString("Failed to adjust pump time", comment: "Error description when pump time failed to sync")
        case .pumpIsBusy:
            return LocalizedString("Action has been canceled, because the pump is busy", comment: "Error description when pump is busy (with bolussing probably)")
        case .bolusTimeoutActive:
            return LocalizedString("A bolus timeout is active. The loop cycle cannot be completed till the timeout is inactive", comment: "Error description when pump has an active blockage")
        case .bolusMaxViolation:
            return LocalizedString("The max bolus limit is reached. Please try a lower amount or increase the limit", comment: "Error description when pump has reached the bolus max")
        case .bolusInsulinLimitViolation:
            return LocalizedString("The max daily insulin limit is reached. Please try a lower amount or increase the limit", comment: "Error description when pump has reached the daily max")
        case .unknown(let message):
            return "Unknown error occured: \(message)"
        }
    }
}
