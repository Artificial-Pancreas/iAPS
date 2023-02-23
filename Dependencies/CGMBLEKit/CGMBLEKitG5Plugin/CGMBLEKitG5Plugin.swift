//
//  CGMBLEKitG5Plugin.swift
//  CGMBLEKitG5Plugin
//
//  Created by Nathaniel Hamming on 2019-12-19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKitUI
import CGMBLEKit
import CGMBLEKitUI

class CGMBLEKitG5Plugin: NSObject, CGMManagerUIPlugin {
    private let log = OSLog(category: "CGMBLEKitG5Plugin")
    
    public var cgmManagerType: CGMManagerUI.Type? {
        return G5CGMManager.self
    }
    
    override init() {
        super.init()
        log.default("Instantiated")
    }
}
