//
//  CGMBLEKitG6Plugin.swift
//  CGMBLEKitG6Plugin
//
//  Created by Nathaniel Hamming on 2019-12-13.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKitUI
import CGMBLEKit
import CGMBLEKitUI

class CGMBLEKitG6Plugin: NSObject, CGMManagerUIPlugin {    
    private let log = OSLog(category: "CGMBLEKitG6Plugin")
    
    public var cgmManagerType: CGMManagerUI.Type? {
        return G6CGMManager.self
    }
    
    override init() {
        super.init()
        log.default("Instantiated")
    }
}
