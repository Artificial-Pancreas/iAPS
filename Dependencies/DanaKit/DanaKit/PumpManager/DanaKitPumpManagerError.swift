//
//  DanaKitErrors.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 09/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

public enum DanaKitPumpManagerError {
    case noConnection
    case failedTempBasalAdjustment
    case failedSuspensionAdjustment
    case failedBasalGeneration
    case failedBasalAdjustment
    case unsupportedTempBasal
}


extension DanaKitPumpManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noConnection:
            return LocalizedString("Failed to make a connection", comment: "Error description when no rileylink connected")
        case .failedTempBasalAdjustment:
            return LocalizedString("Failed to adjust temp basal", comment: "Error description when failed temp adjustment")
        case .failedSuspensionAdjustment:
            return LocalizedString("Failed to adjust suspension", comment: "Error description when failed suspension adjustment")
        case .failedBasalGeneration:
            return LocalizedString("Failed to generate Dana basal program", comment: "Error description when failed generating basal program")
        case .failedBasalAdjustment:
            return LocalizedString("Failed to adjust basal", comment: "Error description when failed basal adjustment")
        case .unsupportedTempBasal:
            return LocalizedString("Setting temp basal is not supported at this time", comment: "Error description when trying to set temp basal")
        }
    }
}
