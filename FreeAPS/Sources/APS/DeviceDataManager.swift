import Combine
import Foundation
import LoopKit
import LoopKitUI
import MinimedKit
import MockKit
import OmniKit
import SwiftDate
import Swinject
import UserNotifications

protocol DeviceDataManager {
    var pumpManager: PumpManagerUI? { get set }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var recommendsLoop: PassthroughSubject<Void, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    func heartbeat()
}

private let staticPumpManagers: [PumpManagerUI.Type] = [
    MinimedPumpManager.self,
    OmnipodPumpManager.self,
    MockPumpManager.self
]

private let staticPumpManagersByIdentifier: [String: PumpManagerUI.Type] = staticPumpManagers.reduce(into: [:]) { map, Type in
    map[Type.managerIdentifier] = Type
}

private let accessLock = NSRecursiveLock(label: "BaseDeviceDataManager.accessLock")

final class BaseDeviceDataManager: DeviceDataManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseDeviceDataManager.processQueue")
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    @Persisted(key: "BaseDeviceDataManager.lastEventDate") var lastEventDate: Date? = nil
    @SyncAccess(lock: accessLock) @Persisted(key: "BaseDeviceDataManager.lastHeartBeatTime") var lastHeartBeatTime: Date =
        .distantPast

    let recommendsLoop = PassthroughSubject<Void, Never>()

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            pumpManager?.delegateQueue = processQueue
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
            if let pumpManager = pumpManager {
                pumpDisplayState.value = PumpDisplayState(name: pumpManager.localizedTitle, image: pumpManager.smallImage)
                pumpName.send(pumpManager.localizedTitle)

                if let omnipod = pumpManager as? OmnipodPumpManager {
                    guard let endTime = omnipod.state.podState?.expiresAt else {
                        pumpExpiresAtDate.send(nil)
                        return
                    }
                    pumpExpiresAtDate.send(endTime)
                }
                pumpManager.setMustProvideBLEHeartbeat(true)
            } else {
                pumpDisplayState.value = nil
            }
        }
    }

    let pumpDisplayState = CurrentValueSubject<PumpDisplayState?, Never>(nil)
    let pumpExpiresAtDate = CurrentValueSubject<Date?, Never>(nil)
    let pumpName = CurrentValueSubject<String, Never>("Pump")

    init(resolver: Resolver) {
        injectServices(resolver)
        setupPumpManager()
        UIDevice.current.isBatteryMonitoringEnabled = true
        updatePumpData()
    }

    func setupPumpManager() {
        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        }
    }

    private func updatePumpData() {
        let now = Date()
        var updateInterval: TimeInterval = 5.minutes.timeInterval

        switch lastHeartBeatTime.timeIntervalSince(now) {
        case let interval where interval < -10.minutes.timeInterval:
            break
        case let interval where interval < -5.minutes.timeInterval:
            updateInterval = 1.minutes.timeInterval
        default:
            break
        }

        let interval = now.timeIntervalSince(lastHeartBeatTime)
        guard interval >= updateInterval else {
            debug(.deviceManager, "Last hearbeat \(interval / 60) min ago, skip updating the pump data")
            return
        }

        heartbeat()
    }

    @SyncAccess(lock: accessLock) private var pumpUpdateInProgress = false

    func heartbeat() {
        guard let pumpManager = pumpManager else {
            debug(.deviceManager, "Pump is not set, skip updating")
            return
        }
        guard !pumpUpdateInProgress else {
            debug(.deviceManager, "Pump update in progress, skip updating")
            return
        }
        debug(.deviceManager, "Start updating the pump data")
        pumpUpdateInProgress = true
        lastHeartBeatTime = Date()
        pumpManager.ensureCurrentPumpData {
            debug(.deviceManager, "Pump Data updated")
            self.pumpUpdateInProgress = false
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
}

extension BaseDeviceDataManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        debug(.deviceManager, "didAdjustPumpClockBy \(adjustment)")
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
        if self.pumpManager == nil, let newPumpManager = pumpManager as? PumpManagerUI {
            self.pumpManager = newPumpManager
        }
        pumpName.send(pumpManager.localizedTitle)
    }

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {
        debug(.deviceManager, "Pump Heartbeat")
        updatePumpData()
    }

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        debug(.deviceManager, "New pump status Bolus: \(status.bolusState)")
        debug(.deviceManager, "New pump status Basal: \(String(describing: status.basalDeliveryState))")

        let batteryPercent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)
        let battery = Battery(
            percent: batteryPercent,
            voltage: nil,
            string: batteryPercent >= 10 ? .normal : .low,
            display: pumpManager?.status.pumpBatteryChargeRemaining != nil
        )
        storage.save(battery, as: OpenAPS.Monitor.battery)
        broadcaster.notify(PumpBatteryObserver.self, on: processQueue) {
            $0.pumpBatteryDidChange(battery)
        }

        if let omnipod = pumpManager as? OmnipodPumpManager {
            guard let endTime = omnipod.state.podState?.expiresAt else {
                pumpExpiresAtDate.send(nil)
                return
            }
            pumpExpiresAtDate.send(endTime)
        }
    }

    func pumpManagerWillDeactivate(_: PumpManager) {
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError error: PumpManagerError) {
        info(.deviceManager, "error: \(error.localizedDescription)")
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation _: Date?,
        completion: @escaping (_ error: Error?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        pumpHistoryStorage.storePumpEvents(events)
        lastEventDate = events.last?.date
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
        dispatchPrecondition(condition: .onQueue(processQueue))
        debug(.deviceManager, "Reservoir Value \(units), at: \(date)")
        storage.save(Decimal(units), as: OpenAPS.Monitor.reservoir)
        broadcaster.notify(PumpReservoirObserver.self, on: processQueue) {
            $0.pumpReservoirDidChange(Decimal(units))
        }

        completion(.success((
            newValue: Reservoir(startDate: Date(), unitVolume: units),
            lastValue: nil,
            areStoredValuesContinuous: true
        )))
    }

    func pumpManagerRecommendsLoop(_: PumpManager) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        pumpUpdateInProgress = false
        debug(.deviceManager, "Recomends loop")
        recommendsLoop.send()
    }

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        lastEventDate ?? Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceDataManager: DeviceManagerDelegate {
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

extension BaseDeviceDataManager: AlertPresenter {
    func issueAlert(_: Alert) {}

    func retractAlert(identifier _: Alert.Identifier) {}
}

// MARK: Others

protocol PumpReservoirObserver {
    func pumpReservoirDidChange(_ reservoir: Decimal)
}

protocol PumpBatteryObserver {
    func pumpBatteryDidChange(_ battery: Battery)
}
