import LoopKit
import LoopKitUI
import MockKit

let staticCGMManagersByIdentifier: [String: CGMManager.Type] = [
    MockCGMManager.pluginIdentifier: MockCGMManager.self
]

var availableStaticCGMManagers: [CGMManagerDescriptor] {
//    if FeatureFlags.allowSimulators {
    [
        CGMManagerDescriptor(identifier: MockCGMManager.pluginIdentifier, localizedTitle: MockCGMManager.localizedTitle)
    ]
//    } else {
//        return []
//    }
}

func CGMManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManager? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? CGMManager.RawStateValue,
          let Manager = staticCGMManagersByIdentifier[managerIdentifier]
    else {
        return nil
    }

    return Manager.init(rawState: rawState)
}

extension CGMManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        [
            "managerIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}
