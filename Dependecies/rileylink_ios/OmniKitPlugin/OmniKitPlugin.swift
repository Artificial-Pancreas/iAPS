//
//  OmniKitPlugin.swift
//  OmniKitPlugin
//
//  Created by Pete Schwamb on 8/24/19.
//  Copyright © 2019 Pete Schwamb. All rights reserved.
//

import Foundation
import LoopKitUI
import OmniKit
import OmniKitUI
import os.log

class OmniKitPlugin: NSObject, LoopUIPlugin {
    private let log = OSLog(category: "OmniKitPlugin")
    
    public var pumpManagerType: PumpManagerUI.Type? {
        return OmnipodPumpManager.self
    }
    
    public var cgmManagerType: CGMManagerUI.Type? {
        return nil
    }
    
    override init() {
        super.init()
        log.default("OmniKitPlugin Instantiated")
    }
}
