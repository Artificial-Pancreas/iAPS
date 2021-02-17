//
//  PodInfoResponseSubType.swift
//  OmniKit
//
//  Created by Eelke Jager on 15/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public protocol PodInfo {
    init(encodedData: Data) throws
    var podInfoType: PodInfoResponseSubType { get }
    var data: Data { get }
    
}

public enum PodInfoResponseSubType: UInt8, Equatable {
    case normal                      = 0x00
    case configuredAlerts            = 0x01 // Returns information on configured alerts
    case detailedStatus              = 0x02 // Returned on any pod fault
    case pulseLogPlus                = 0x03 // Returns up to the last 60 pulse log entries plus additional info
    case activationTime              = 0x05 // Returns activation date, elapsed time, and fault code
    case pulseLogRecent              = 0x50 // Returns the last 50 pulse log entries
    case pulseLogPrevious            = 0x51 // Like 0x50, but returns up to the previous 50 entries before the last 50
    
    public var podInfoType: PodInfo.Type {
        switch self {
        case .normal:
            return StatusResponse.self as! PodInfo.Type
        case .configuredAlerts:
            return PodInfoConfiguredAlerts.self
        case .detailedStatus:
            return DetailedStatus.self
        case .pulseLogPlus:
            return PodInfoPulseLogPlus.self
        case .activationTime:
            return PodInfoActivationTime.self
        case .pulseLogRecent:
            return PodInfoPulseLogRecent.self
        case .pulseLogPrevious:
            return PodInfoPulseLogPrevious.self
        }
    }
}
