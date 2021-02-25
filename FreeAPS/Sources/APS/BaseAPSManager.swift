import Combine
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import MinimedKitUI
import NightscoutUploadKit
import OmniKit
import RileyLinkBLEKit
import RileyLinkKit
import RileyLinkKitUI
import SwiftDate
import Swinject
import UserNotifications

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
    map[Type.managerIdentifier] = Type
}

final class BaseAPSManager: APSManager, Injectable {
    private var openAPS: OpenAPS!

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
            if let pumpManager = pumpManager {
                pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
            } else {
                pumpDisplayState.value = nil
            }
        }
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: resolver.resolve(FileStorage.self)!)
        setupPumpManager()
    }

    private func setupPumpManager() {
        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        }
    }

    func runTest() {
        openAPS.test()
    }

    private func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
              let Manager = pumpManagerTypeFromRawValue(rawValue)
        else {
            return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return staticPumpManagersByIdentifier[managerIdentifier]
    }
}

extension BaseAPSManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy _: TimeInterval) {
//        log.debug("didAdjustPumpClockBy %@", adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        print("[APSManager] Pump Heartbeat")
        pumpManager.ensureCurrentPumpData {
            print("[APSManager] Pump Data updated")
        }
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        print("[APSManager] new pump status Bolus: \(status.bolusState)")
        print("[APSManager] new pump status Basal: \(String(describing: status.basalDeliveryState))")
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        print("[APSManager] error: \(error.localizedDescription)")
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        print("[APSManager] new pump events: \(events.compactMap(\.dose?.type))")
        completion(nil)
    }

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {
        print("[APSManager] Reservoir Value \(units), at: \(date)")
        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        print("[APSManager] recomends loop")
//        pumpManager.enactBolus(units: 0.1, automatic: true) { _ in
//            print("[APSManager] Bolus done")
//        }
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension BaseAPSManager: DeviceManagerDelegate {
    func scheduleNotification(
        for _: DeviceManager,
        identifier: String,
        content: UNNotificationContent,
        trigger: UNNotificationTrigger?
    ) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        DispatchQueue.main.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clearNotification(for _: DeviceManager, identifier: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    func removeNotificationRequests(for _: DeviceManager, identifiers: [String]) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deviceManager(
        _: DeviceManager,
        logEventForDeviceIdentifier _: String?,
        type _: DeviceLogEntryType,
        message _: String,
        completion _: ((Error?) -> Void)?
    ) {}
}

// MARK: - AlertPresenter

extension BaseAPSManager: AlertPresenter {
    func issueAlert(_: Alert) {}

    func retractAlert(identifier _: Alert.Identifier) {}
}
