import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!

        @Published var cgmIdentifierToSetUp: String? = nil

        @Published var transmitterID = ""
        @Published var smoothGlucose = false
        @Published var cgmTransmitterDeviceAddress: String? = nil
        @Published var sensorDays: Double = 10

        @Published var appGroupSourceType: AppGroupSourceType? = nil

        override func subscribe() {
            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress
            appGroupSourceType = settingsManager.settings.appGroupSourceType

//            switch cgm {
//            case .nightscout:
//                sensorDays = CGMType.nightscout.expiration
//            case .xdrip:
//                sensorDays = sensorDays
//            case .dexcomG5:
//                sensorDays = CGMType.dexcomG5.expiration
//            case .dexcomG6:
//                sensorDays = CGMType.dexcomG6.expiration
//            case .dexcomG7:
//                sensorDays = CGMType.dexcomG7.expiration
//            case .simulator:
//                sensorDays = sensorDays
//            case .libreTransmitter:
//                sensorDays = CGMType.libreTransmitter.expiration
//            case .glucoseDirect:
//                sensorDays = sensorDays
//            case .enlite:
//                sensorDays = CGMType.enlite.expiration
//            }

            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
            subscribeSetting(\.sensorDays, on: $sensorDays) { sensorDays = $0 }
            subscribeSetting(\.appGroupSourceType, on: $appGroupSourceType) { appGroupSourceType = $0 }
        }

        func removePumpAsCGM() {
            deviceManager.removePumpAsCGM()
        }
    }
}

extension CGM.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        cgmIdentifierToSetUp = nil
    }
}

//
// extension CGM.StateModel: CGMManagerOnboardingDelegate {
//    func cgmManagerOnboarding(didCreateCGMManager manager: LoopKitUI.CGMManagerUI) {
//        // Possibility add the dexcom number !
//        if let dexcomG6Manager: G6CGMManager = manager as? G6CGMManager {
//            UserDefaults.standard.dexcomTransmitterID = dexcomG6Manager.transmitter.ID
//
//        } else if let dexcomG5Manager: G5CGMManager = manager as? G5CGMManager {
//            UserDefaults.standard.dexcomTransmitterID = dexcomG5Manager.transmitter.ID
//        }
////        cgmManager.updateGlucoseSource()
//    }
//
//    func cgmManagerOnboarding(didOnboardCGMManager _: LoopKitUI.CGMManagerUI) {
//        // nothing to do ?
//    }
// }
