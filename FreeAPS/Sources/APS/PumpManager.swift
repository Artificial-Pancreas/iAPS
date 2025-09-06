import Foundation
import LoopKit
import LoopKitUI
import MockKit
import MockKitUI

let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = [
    MockPumpManager.pluginIdentifier: MockPumpManager.self
]

var availableStaticPumpManagers: [PumpManagerDescriptor] {
//    if FeatureFlags.allowSimulators {
    [
        PumpManagerDescriptor(identifier: MockPumpManager.pluginIdentifier, localizedTitle: MockPumpManager.localizedTitle)
    ]
//    } else {
//        return []
//    }
}

// extension PumpManager {
//
//    typealias RawValue = [String: Any]
//
//    var rawValue: RawValue {
//        return [
//            "managerIdentifier": self.pluginIdentifier,
//            "state": self.rawState
//        ]
//    }
// }
