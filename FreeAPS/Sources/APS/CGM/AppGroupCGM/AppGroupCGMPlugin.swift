import LoopKitUI
import NightscoutRemoteCGM
import os.log

class AppGroupCGMPlugin: NSObject, CGMManagerUIPlugin {
    public var cgmManagerType: CGMManagerUI.Type? {
        AppGroupCGM.self
    }

    override init() {
        super.init()
    }
}
