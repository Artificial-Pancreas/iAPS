//
//  CGMBLEKitG7Plugin.swift
//  CGMBLEKitG7Plugin
//
//  Created by Pete Schwamb on 9/24/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKitUI
import G7SensorKit
import G7SensorKitUI

class G7SensorPlugin: NSObject, CGMManagerUIPlugin {
    private let log = OSLog(category: "G7Plugin")

    public var cgmManagerType: CGMManagerUI.Type? {
        return G7CGMManager.self
    }

    override init() {
        super.init()
        log.default("Instantiated")
    }
}
