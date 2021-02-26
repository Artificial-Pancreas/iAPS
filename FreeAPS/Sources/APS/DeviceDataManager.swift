import Combine
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import OmniKit
import SwiftDate
import UserNotifications

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
    map[Type.managerIdentifier] = Type
}

final class DeviceDataManager {
    private let storage: FileStorage

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

    init(storage: FileStorage) {
        self.storage = storage
        setupPumpManager()
    }

    func setupPumpManager() {
        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        }
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

    private func storePumpEvents(_ events: [NewPumpEvent]) {
        print(
            "[DeviceDataManager] new pump events: \(events.map(\.title))"
        )

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal

        let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
            switch event.type {
            case .bolus:
                guard let dose = event.dose else { return [] }
                let decimal = Decimal(string: dose.unitsInDeliverableIncrements.description)
                return [PumpHistoryEvent(
                    id: event.raw.md5String,
                    type: .bolus,
                    timestamp: event.date,
                    amount: decimal,
                    duration: nil,
                    durationMin: nil,
                    rate: nil,
                    temp: nil
                )]
            default:
                return []
            }
        }

        do {
            try storage.append(eventsToStore, to: OpenAPS.Monitor.pumpHistory, uniqBy: \.id)
        } catch {
            try? storage.save(eventsToStore, as: OpenAPS.Monitor.pumpHistory)
        }
    }
}

extension DeviceDataManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy _: TimeInterval) {
//        log.debug("didAdjustPumpClockBy %@", adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        print("[DeviceDataManager] Pump Heartbeat")
        pumpManager.ensureCurrentPumpData {
            print("[DeviceDataManager] Pump Data updated")
        }
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        print("[DeviceDataManager] new pump status Bolus: \(status.bolusState)")
        print("[DeviceDataManager] new pump status Basal: \(String(describing: status.basalDeliveryState))")
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        print("[DeviceDataManager] error: \(error.localizedDescription)")
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        storePumpEvents(events)
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
        print("[DeviceDataManager] Reservoir Value \(units), at: \(date)")
        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        print("[DeviceDataManager] recomends loop")
//        pumpManager.enactBolus(units: 0.1, automatic: true) { _ in
//            print("[DeviceDataManager] Bolus done")
//        }
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension DeviceDataManager: DeviceManagerDelegate {
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

extension DeviceDataManager: AlertPresenter {
    func issueAlert(_: Alert) {}

    func retractAlert(identifier _: Alert.Identifier) {}
}
