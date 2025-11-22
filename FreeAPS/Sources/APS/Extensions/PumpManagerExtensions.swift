import LoopKit
import LoopKitUI

extension PumpManager {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        [
            "managerIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}
