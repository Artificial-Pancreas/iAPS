//
//  MinimedPumpManagerError.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

public enum MinimedPumpManagerError: Error {
    case noRileyLink
    case bolusInProgress
    case pumpSuspended
    case insulinTypeNotConfigured
    case noDate  // TODO: This is less of an error and more of a precondition/assertion state
    case tuneFailed(LocalizedError)
    case commsError(LocalizedError)
    case storageFailure
}


extension MinimedPumpManagerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noRileyLink:
            return LocalizedString("No RileyLink Connected", comment: "Error description when no rileylink connected")
        case .bolusInProgress:
            return LocalizedString("Bolus in Progress", comment: "Error description when failure due to bolus in progress")
        case .pumpSuspended:
            return LocalizedString("Pump is Suspended", comment: "Error description when failure due to pump suspended")
        case .insulinTypeNotConfigured:
            return LocalizedString("Insulin Type is not configured", comment: "Error description for MinimedPumpManagerError.insulinTypeNotConfigured")
        case .noDate:
            return nil
        case .tuneFailed(let error):
            return [LocalizedString("RileyLink radio tune failed", comment: "Error description for tune failure"), error.errorDescription].compactMap({ $0 }).joined(separator: ": ")
        case .commsError(let error):
            return error.errorDescription
        case .storageFailure:
            return LocalizedString("Unable to store pump data", comment: "Error description when storage fails")
        }
    }

    public var failureReason: String? {
        switch self {
        case .tuneFailed(let error):
            return error.failureReason
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noRileyLink:
            return LocalizedString("Make sure your RileyLink is nearby and powered on", comment: "Recovery suggestion")
        case .insulinTypeNotConfigured:
            return LocalizedString("Go to pump settings and select insulin type", comment: "Recovery suggestion for MinimedPumpManagerError.insulinTypeNotConfigured")
        case .tuneFailed(let error):
            return error.recoverySuggestion
        default:
            return nil
        }
    }
}
