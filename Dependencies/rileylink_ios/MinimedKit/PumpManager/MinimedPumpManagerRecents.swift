//
//  MinimedPumpManagerRecents.swift
//  MinimedKit
//
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKit

public struct MinimedPumpManagerRecents: Equatable {

    internal enum EngageablePumpState: Equatable {
        case engaging
        case disengaging
        case stable
    }

    internal var suspendEngageState: EngageablePumpState = .stable

    internal var bolusEngageState: EngageablePumpState = .stable

    internal var tempBasalEngageState: EngageablePumpState = .stable

    var lastAddedPumpEvents: Date = .distantPast
    
    var lastContinuousReservoir: Date = .distantPast

    var latestPumpStatus: PumpStatus? = nil

    var latestPumpStatusFromMySentry: MySentryPumpStatusMessageBody? = nil {
        didSet {
            if let sensorState = latestPumpStatusFromMySentry {
                self.sensorState = EnliteSensorDisplayable(sensorState)
            }
        }
    }

    var sensorState: EnliteSensorDisplayable? = nil
}

extension MinimedPumpManagerRecents: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        ### MinimedPumpManagerRecents
        suspendEngageState: \(suspendEngageState)
        bolusEngageState: \(bolusEngageState)
        tempBasalEngageState: \(tempBasalEngageState)
        lastAddedPumpEvents: \(lastAddedPumpEvents)
        latestPumpStatus: \(String(describing: latestPumpStatus))
        lastContinuousReservoir: \(lastContinuousReservoir)
        latestPumpStatusFromMySentry: \(String(describing: latestPumpStatusFromMySentry))
        sensorState: \(String(describing: sensorState))
        """
    }
}
