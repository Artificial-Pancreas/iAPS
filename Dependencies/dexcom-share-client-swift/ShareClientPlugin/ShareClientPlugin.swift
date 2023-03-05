//
//  ShareClientPlugin.swift
//  ShareClientPlugin
//
//  Created by Nathaniel Hamming on 2019-12-19.
//  Copyright © 2019 Mark Wilson. All rights reserved.
//

import os.log
import LoopKitUI
import ShareClient
import ShareClientUI

class ShareClientPlugin: NSObject, CGMManagerUIPlugin {
    private let log = OSLog(category: "ShareClientPlugin")
    
    public var cgmManagerType: CGMManagerUI.Type? {
        return ShareClientManager.self
    }
    
    override init() {
        super.init()
        log.default("Instantiated")
    }
}
