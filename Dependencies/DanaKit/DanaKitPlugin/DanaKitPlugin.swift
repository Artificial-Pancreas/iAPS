//
//  DanaKitPlugin.swift
//  DanaKit
//
//  Based on OmniKitPlugin/OmniKitPlugin.swift
//  Created by Randall Knutson on 09/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI
import OmniBLE
import os.log

class DanaKitPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "DanaKitPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        return DanaKitPumpManager.self
    }

    public var cgmManagerType: CGMManagerUI.Type? {
        return nil
    }

    override init() {
        super.init()
        log.default("DanaKitPlugin Instantiated")
    }
}
