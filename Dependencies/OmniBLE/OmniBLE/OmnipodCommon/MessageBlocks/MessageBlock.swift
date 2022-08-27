//
//  MessageBlock.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/MessageBlock.swift
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import Foundation

public enum MessageBlockError: Error {
    case notEnoughData
    case unknownBlockType(rawVal: UInt8)
    case parseError
}

// See https://github.com/openaps/openomni/wiki/Message-Types
public enum MessageBlockType: UInt8 {
    case versionResponse    = 0x01
    case podInfoResponse    = 0x02
    case setupPod           = 0x03
    case errorResponse      = 0x06
    case assignAddress      = 0x07
    case faultConfig        = 0x08
    case getStatus          = 0x0e
    case acknowledgeAlert   = 0x11
    case basalScheduleExtra = 0x13
    case tempBasalExtra     = 0x16
    case bolusExtra         = 0x17
    case configureAlerts    = 0x19
    case setInsulinSchedule = 0x1a
    case deactivatePod      = 0x1c
    case statusResponse     = 0x1d
    case beepConfig         = 0x1e
    case cancelDelivery     = 0x1f
    
    public var blockType: MessageBlock.Type {
        switch self {
        case .versionResponse:
            return VersionResponse.self
        case .acknowledgeAlert:
            return AcknowledgeAlertCommand.self
        case .podInfoResponse:
            return PodInfoResponse.self
        case .setupPod:
            return SetupPodCommand.self
        case .errorResponse:
            return ErrorResponse.self
        case .assignAddress:
            return AssignAddressCommand.self
        case .getStatus:
            return GetStatusCommand.self
        case .basalScheduleExtra:
            return BasalScheduleExtraCommand.self
        case .bolusExtra:
            return BolusExtraCommand.self
        case .configureAlerts:
            return ConfigureAlertsCommand.self
        case .setInsulinSchedule:
            return SetInsulinScheduleCommand.self
        case .deactivatePod:
            return DeactivatePodCommand.self
        case .statusResponse:
            return StatusResponse.self
        case .tempBasalExtra:
            return TempBasalExtraCommand.self
        case .beepConfig:
            return BeepConfigCommand.self
        case .cancelDelivery:
            return CancelDeliveryCommand.self
        case .faultConfig:
            return FaultConfigCommand.self
        }
    }
}
    
public protocol MessageBlock {
    init(encodedData: Data) throws

    var blockType: MessageBlockType { get }
    var data: Data { get  }
}

public protocol NonceResyncableMessageBlock : MessageBlock {
    var nonce: UInt32 { get set }
}
