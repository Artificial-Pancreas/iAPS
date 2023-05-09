//
//  TimestampedPumpEvent.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/8/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public protocol TimestampedPumpEvent: PumpEvent {
    
    var timestamp: DateComponents {
        get
    }
}
