//
//  OmniKitPlugin.swift
//  OmniKitPlugin
//
//  Created by Pete Schwamb on 8/24/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import os.log
import LoopKitUI
import OmniKit
import OmniKitUI

class OmniKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "OmniKitPlugin")
    
    public var pumpManagerType: PumpManagerUI.Type? {
        return OmnipodPumpManager.self
    }
    
    override init() {
        super.init()
        log.default("Instantiated")
    }
}
