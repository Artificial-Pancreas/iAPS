import Foundation
import LoopKit
import RileyLinkBLEKit
import RileyLinkKit

extension UserDefaults {
    private enum Key: String {
        case pumpManagerRawValue = "com.rileylink.PumpManagerRawValue"
        case rileyLinkConnectionManagerState = "com.rileylink.RileyLinkConnectionManagerState"
    }

    var pumpManagerRawValue: PumpManager.RawStateValue? {
        get {
            dictionary(forKey: Key.pumpManagerRawValue.rawValue)
        }
        set {
            set(newValue, forKey: Key.pumpManagerRawValue.rawValue)
        }
    }

    var rileyLinkConnectionManagerState: RileyLinkConnectionState? {
        get {
            guard let rawValue = dictionary(forKey: Key.rileyLinkConnectionManagerState.rawValue)
            else {
                return nil
            }
            return RileyLinkConnectionState(rawValue: rawValue)
        }
        set {
            set(newValue?.rawValue, forKey: Key.rileyLinkConnectionManagerState.rawValue)
        }
    }
}
