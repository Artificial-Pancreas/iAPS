import Foundation
import LoopKit
import RileyLinkBLEKit
import RileyLinkKit

extension UserDefaults {
    private enum Key: String {
        case legacyPumpManagerState = "com.rileylink.PumpManagerRawValue"
        case legacyCGMManagerState = "cgmManagerRawValue"
    }

    var legacyPumpManagerRawValue: PumpManager.RawStateValue? {
        get {
            dictionary(forKey: Key.legacyPumpManagerState.rawValue)
        }
        set {
            set(newValue, forKey: Key.legacyPumpManagerState.rawValue)
        }
    }

    func clearLegacyPumpManagerRawValue() {
        set(nil, forKey: Key.legacyPumpManagerState.rawValue)
    }

    var legacyCgmManagerRawValue: CGMManager.RawStateValue? {
        get { object(forKey: Key.legacyCGMManagerState.rawValue) as? CGMManager.RawStateValue }
        set { set(newValue, forKey: Key.legacyCGMManagerState.rawValue) }
    }

    func clearLegacyCGMManagerRawValue() {
        set(nil, forKey: Key.legacyCGMManagerState.rawValue)
    }
}
