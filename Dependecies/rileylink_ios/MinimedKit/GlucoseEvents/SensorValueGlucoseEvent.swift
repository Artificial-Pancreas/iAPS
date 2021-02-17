//
//  SensorValueGlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/11/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

/// An event that contains an sgv
public protocol SensorValueGlucoseEvent: RelativeTimestampedGlucoseEvent {
    
    var sgv: Int {
        get
    }
}
