//
//  MinimedKitPlugin.swift
//  MinimedKitPlugin
//
//  Created by Pete Schwamb on 8/24/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import os.log
import LoopKitUI
import MinimedKit
import MinimedKitUI

class MinimedKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "MinimedKitPlugin")
    
    public var pumpManagerType: PumpManagerUI.Type? {
        return MinimedPumpManager.self
    }
    
    override init() {
        super.init()
        log.default("Instantiated")
    }
}
