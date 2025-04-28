//
//  PumpAlarmType.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 28/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import Foundation
import LoopKit

extension PumpAlarmType {
    static func fromParam8(_ value: UInt8?) -> PumpAlarmType? {
        guard let value = value else {
            return nil
        }
        
        switch(value) {
        case 0x50:
            return PumpAlarmType.other("Basal Compare")
        case 0x52:
            return PumpAlarmType.lowInsulin
        case 0x43:
            return PumpAlarmType.other("Check")
        case 0x4f:
            return PumpAlarmType.occlusion
        case 0x4d:
            return PumpAlarmType.other("Basal maximum exceeded")
        case 0x44:
            return PumpAlarmType.other("Daily max insulin reached")
        case 0x42:
            return PumpAlarmType.lowPower
        case 0x53:
            return PumpAlarmType.noPower
        default:
            return nil
        }
    }
}
