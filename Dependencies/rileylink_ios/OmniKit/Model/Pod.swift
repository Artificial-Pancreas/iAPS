//
//  Pod.swift
//  OmniKit
//
//  Created by Pete Schwamb on 4/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct Pod {
    // Volume of U100 insulin in one motor pulse
    // Must agree with value returned by pod during the pairing process.
    public static let pulseSize: Double = 0.05

    // Number of pulses required to deliver one unit of U100 insulin
    public static let pulsesPerUnit: Double = 1 / Pod.pulseSize

    // Seconds per pulse for boluses
    // Checked to verify it agrees with value returned by pod during the pairing process.
    public static let secondsPerBolusPulse: Double = 2

    // Units per second for boluses
    public static let bolusDeliveryRate: Double = Pod.pulseSize / Pod.secondsPerBolusPulse

    // Seconds per pulse for priming/cannula insertion
    // Checked to verify it agrees with value returned by pod during the pairing process.
    public static let secondsPerPrimePulse: Double = 1

    // Units per second for priming/cannula insertion
    public static let primeDeliveryRate: Double = Pod.pulseSize / Pod.secondsPerPrimePulse

    // User configured time before expiration advisory (PDM allows 1-24 hours)
    public static let expirationAlertWindow = TimeInterval(hours: 2)

    // Expiration advisory window: time after expiration alert, and end of service imminent alarm
    public static let expirationAdvisoryWindow = TimeInterval(hours: 7)

    // End of service imminent window, relative to pod end of service
    public static let endOfServiceImminentWindow = TimeInterval(hours: 1)

    // Total pod service time. A fault is triggered if this time is reached before pod deactivation.
    // Checked to verify it agrees with value returned by pod during the pairing process.
    public static let serviceDuration = TimeInterval(hours: 80)

    // Nomimal pod life (72 hours)
    public static let nominalPodLife = Pod.serviceDuration - Pod.endOfServiceImminentWindow - Pod.expirationAdvisoryWindow

    // Maximum reservoir level reading
    public static let maximumReservoirReading: Double = 50

    // Reservoir Capacity
    public static let reservoirCapacity: Double = 200

    // Supported basal rates
    public static let supportedBasalRates: [Double] = (1...600).map { Double($0) / Double(pulsesPerUnit) }

    // Maximum number of basal schedule entries supported
    public static let maximumBasalScheduleEntryCount: Int = 24

    // Minimum duration of a single basal schedule entry
    public static let minimumBasalScheduleEntryDuration = TimeInterval.minutes(30)

    // Default amount for priming bolus using secondsPerPrimePulse timing.
    // Checked to verify it agrees with value returned by pod during the pairing process.
    public static let primeUnits = 2.6

    // Default amount for cannula insertion bolus using secondsPerPrimePulse timing.
    // Checked to verify it agrees with value returned by pod during the pairing process.
    public static let cannulaInsertionUnits = 0.5

    public static let cannulaInsertionUnitsExtra = 0.0 // edit to add a fixed additional amount of insulin during cannula insertion

    // Default and limits for expiration reminder alerts
    public static let expirationReminderAlertDefaultTimeBeforeExpiration = TimeInterval.hours(2)
    public static let expirationReminderAlertMinTimeBeforeExpiration = TimeInterval.hours(1)
    public static let expirationReminderAlertMaxTimeBeforeExpiration = TimeInterval.hours(24)
}

// DeliveryStatus used in StatusResponse and DetailedStatus
public enum DeliveryStatus: UInt8, CustomStringConvertible {
    case suspended = 0
    case scheduledBasal = 1
    case tempBasalRunning = 2
    case priming = 4
    case bolusInProgress = 5
    case bolusAndTempBasal = 6
    
    public var bolusing: Bool {
        return self == .bolusInProgress || self == .bolusAndTempBasal
    }
    
    public var tempBasalRunning: Bool {
        return self == .tempBasalRunning || self == .bolusAndTempBasal
    }

    public var description: String {
        switch self {
        case .suspended:
            return LocalizedString("Suspended", comment: "Delivery status when insulin delivery is suspended")
        case .scheduledBasal:
            return LocalizedString("Scheduled basal", comment: "Delivery status when scheduled basal is running")
        case .tempBasalRunning:
            return LocalizedString("Temp basal running", comment: "Delivery status when temp basal is running")
        case .priming:
            return LocalizedString("Priming", comment: "Delivery status when pod is priming")
        case .bolusInProgress:
            return LocalizedString("Bolusing", comment: "Delivery status when bolusing")
        case .bolusAndTempBasal:
            return LocalizedString("Bolusing with temp basal", comment: "Delivery status when bolusing and temp basal is running")
        }
    }
}
