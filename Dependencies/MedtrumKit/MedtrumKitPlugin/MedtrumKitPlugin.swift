import LoopKitUI
import MedtrumKit
import os.log

class MedtrumKitPlugin: NSObject, PumpManagerUIPlugin {
    public var pumpManagerType: PumpManagerUI.Type? {
        MedtrumPumpManager.self
    }

    override init() {
        super.init()
    }
}
