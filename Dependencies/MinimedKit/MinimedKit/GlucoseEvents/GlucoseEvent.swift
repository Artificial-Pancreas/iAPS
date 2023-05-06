//
//  GlucoseEvent.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

public protocol GlucoseEvent: DictionaryRepresentable {
    
    init?(availableData: Data, relativeTimestamp: DateComponents)
    
    var rawData: Data {
        get
    }
    
    var length: Int {
        get
    }
    
    var timestamp: DateComponents {
        get
    }
}
