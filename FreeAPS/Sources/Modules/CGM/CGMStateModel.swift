import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI
import UIKit

extension CGM {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var deviceManager: DeviceDataManager!
        @Injected() var calendarManager: CalendarManager!

        @Published var cgmIdentifierToSetUp: String? = nil

        @Published var transmitterID = ""
        @Published var smoothGlucose = false
        @Published var createCalendarEvents = false
        @Published var displayCalendarIOBandCOB = false
        @Published var displayCalendarEmojis = false
        @Published var calendarIDs: [String] = []
        @Published var currentCalendarID: String = ""
        @Persisted(key: "CalendarManager.currentCalendarID") var storedCalendarID: String? = nil
        @Published var cgmTransmitterDeviceAddress: String? = nil
        @Published var sensorDays: Double = 10

        override func subscribe() {
            currentCalendarID = storedCalendarID ?? ""
            calendarIDs = calendarManager.calendarIDs()
            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress

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

            subscribeSetting(\.useCalendar, on: $createCalendarEvents) { createCalendarEvents = $0 }
            subscribeSetting(\.displayCalendarIOBandCOB, on: $displayCalendarIOBandCOB) { displayCalendarIOBandCOB = $0 }
            subscribeSetting(\.displayCalendarEmojis, on: $displayCalendarEmojis) { displayCalendarEmojis = $0 }
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
            subscribeSetting(\.sensorDays, on: $sensorDays) { sensorDays = $0 }

            $createCalendarEvents
                .removeDuplicates()
                .flatMap { [weak self] ok -> AnyPublisher<Bool, Never> in
                    guard ok, let self = self else { return Just(false).eraseToAnyPublisher() }
                    return self.calendarManager.requestAccessIfNeeded()
                }
                .map { [weak self] ok -> [String] in
                    guard ok, let self = self else { return [] }
                    return self.calendarManager.calendarIDs()
                }
                .receive(on: DispatchQueue.main)
                .weakAssign(to: \.calendarIDs, on: self)
                .store(in: &lifetime)

            $currentCalendarID
                .removeDuplicates()
                .sink { [weak self] id in
                    guard id.isNotEmpty else {
                        self?.calendarManager.currentCalendarID = nil
                        return
                    }
                    self?.calendarManager.currentCalendarID = id
                }
                .store(in: &lifetime)
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
