//
//  MinimedKitPlugin.swift
//  MinimedKitPlugin
//
//  Created by Pete Schwamb on 8/24/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKitUI
import MinimedKit
import MinimedKitUI
import os.log

class MinimedKitPlugin: NSObject, LoopUIPlugin {
    private let log = OSLog(category: "MinimedKitPlugin")
    
    public var pumpManagerType: PumpManagerUI.Type? {
        return MinimedPumpManager.self
    }
    
    public var cgmManagerType: CGMManagerUI.Type? {
        return nil
    }
    
    override init() {
        super.init()
        log.default("MinimedKitPlugin Instantiated")
    }
}
