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
import UserNotifications

protocol DeviceDataManager {
    var rileyLinkConnectionManager: RileyLinkConnectionManager! { get }
}

final class BaseDeviceManager: DeviceDataManager {
    private(set) var rileyLinkConnectionManager: RileyLinkConnectionManager!

    var pumpManager: PumpManagerUI? {
        didSet {
            pumpManager?.pumpManagerDelegate = self
            UserDefaults.standard.pumpManagerRawValue = pumpManager?.rawValue
        }
    }

    @Persisted(key: "BaseDeviceManager.connectionState") var connectionState: RileyLinkConnectionManagerState? = nil

    init() {
        if let state = connectionState {
            rileyLinkConnectionManager = RileyLinkConnectionManager(state: state)
        } else {
            rileyLinkConnectionManager = RileyLinkConnectionManager(autoConnectIDs: [])
        }

        rileyLinkConnectionManager.delegate = self
        rileyLinkConnectionManager.setScanningEnabled(true)

        if let pumpManagerRawValue = UserDefaults.standard.pumpManagerRawValue {
            pumpManager = PumpManagerFromRawValue(
                pumpManagerRawValue,
                rileyLinkDeviceProvider: rileyLinkConnectionManager.deviceProvider
            ) as? PumpManagerUI
            pumpManager?.pumpManagerDelegate = self
        }
    }
}

extension BaseDeviceManager: RileyLinkConnectionManagerDelegate {
    func rileyLinkConnectionManager(_: RileyLinkConnectionManager, didChange state: RileyLinkConnectionManagerState)
    {
        connectionState = state
    }
}

extension BaseDeviceManager: PumpManagerDelegate {
    func pumpManager(_: PumpManager, didAdjustPumpClockBy _: TimeInterval) {
//        log.debug("didAdjustPumpClockBy %@", adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        UserDefaults.standard.pumpManagerRawValue = pumpManager.rawValue
    }

    func pumpManagerBLEHeartbeatDidFire(_: PumpManager) {}

    func pumpManagerMustProvideBLEHeartbeat(_: PumpManager) -> Bool {
        true
    }

    func pumpManager(_: PumpManager, didUpdate _: PumpManagerStatus, oldStatus _: PumpManagerStatus) {}

    func pumpManagerWillDeactivate(_: PumpManager) {
        pumpManager = nil
    }

    func pumpManager(_: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents _: Bool) {}

    func pumpManager(_: PumpManager, didError _: PumpManagerError) {
//        log.error("pumpManager didError %@", String(describing: error))
    }

    func pumpManager(
        _: PumpManager,
        hasNewPumpEvents _: [NewPumpEvent],
        lastReconciliation _: Date?,
        completion _: @escaping (_ error: Error?) -> Void
    ) {}

    func pumpManager(
        _: PumpManager,
        didReadReservoirValue _: Double,
        at _: Date,
        completion _: @escaping (Result<
            (newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool),
            Error
        >) -> Void
    ) {}

    func pumpManagerRecommendsLoop(_: PumpManager) {}

    func startDateToFilterNewPumpEvents(for _: PumpManager) -> Date {
        Date().addingTimeInterval(-2.hours.timeInterval)
    }
}

// MARK: - DeviceManagerDelegate

extension BaseDeviceManager: DeviceManagerDelegate {
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

extension BaseDeviceManager: AlertPresenter {
    func issueAlert(_: Alert) {}

    func retractAlert(identifier _: Alert.Identifier) {}
}

extension RileyLinkConnectionManagerState: Codable {
    enum CodingKeys: CodingKey {
        case autoConnectIDs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let ids = try? container.decode([String].self, forKey: CodingKeys.autoConnectIDs) {
            self.init(autoConnectIDs: Set(ids))
            return
        }
        self.init(autoConnectIDs: [])
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Array(autoConnectIDs), forKey: CodingKeys.autoConnectIDs)
    }
}

extension PumpManager {
    var rawValue: [String: Any] {
        [
            "managerIdentifier": type(of: self).managerIdentifier,
            "state": rawState
        ]
    }
}

func PumpManagerFromRawValue(_ rawValue: [String: Any], rileyLinkDeviceProvider: RileyLinkDeviceProvider) -> PumpManager? {
    guard let managerIdentifier = rawValue["managerIdentifier"] as? String,
          let rawState = rawValue["state"] as? PumpManager.RawStateValue
    else {
        return nil
    }

    switch managerIdentifier {
    case MinimedPumpManager.managerIdentifier:
        guard let state = MinimedPumpManagerState(rawValue: rawState) else {
            return nil
        }
        return MinimedPumpManager(state: state, rileyLinkDeviceProvider: rileyLinkDeviceProvider)
    case OmnipodPumpManager.managerIdentifier:
        guard let state = OmnipodPumpManagerState(rawValue: rawState) else {
            return nil
        }
        return OmnipodPumpManager(state: state, rileyLinkDeviceProvider: rileyLinkDeviceProvider)
    default:
        return nil
    }
}
