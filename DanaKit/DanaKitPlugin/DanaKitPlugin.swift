import Foundation
import LoopKitUI
import DanaKit
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

