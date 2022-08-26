//
//  OmniBLEPlugin.swift
//  OmniBLE
//
//  Based on OmniKitPlugin/OmniKitPlugin.swift
//  Created by Randall Knutson on 09/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKitUI
import OmniBLE
import os.log

class OmniBLEPlugin: NSObject, PumpManagerUIPlugin {
    private let log = OSLog(category: "OmniBLEPlugin")

    public var pumpManagerType: PumpManagerUI.Type? {
        return OmniBLEPumpManager.self
    }

    public var cgmManagerType: CGMManagerUI.Type? {
        return nil
    }

    override init() {
        super.init()
        log.default("OmniBLEPlugin Instantiated")
    }
}
