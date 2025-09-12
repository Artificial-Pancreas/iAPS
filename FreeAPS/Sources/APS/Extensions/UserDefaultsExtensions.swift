import Foundation
import LoopKit
import RileyLinkBLEKit
import RileyLinkKit

extension UserDefaults {
    private enum Key: String {
        case pumpManagerRawValue = "com.rileylink.PumpManagerRawValue"
    }

    var pumpManagerRawValue: PumpManager.RawStateValue? {
        get {
            dictionary(forKey: Key.pumpManagerRawValue.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerRawValue.rawValue)
        }
    }

    var cgmManagerRawValue: CGMManager.RawStateValue? {
        get { object(forKey: "cgmManagerRawValue") as? CGMManager.RawStateValue }
        set { set(newValue, forKey: "cgmManagerRawValue") }
    }
}
