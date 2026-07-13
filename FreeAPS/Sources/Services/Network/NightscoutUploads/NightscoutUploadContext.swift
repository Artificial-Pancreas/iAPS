import Foundation
import UIKit

final class NightscoutUploadContext: Sendable {
    let apiProvider: NightscoutAPIProvider
    let appCoordinator: AppCoordinator
    let reachabilityManager: ReachabilityManager
    let storage: FileStorage

    init(
        apiProvider: NightscoutAPIProvider,
        appCoordinator: AppCoordinator,
        reachabilityManager: ReachabilityManager,
        storage: FileStorage
    ) {
        self.apiProvider = apiProvider
        self.appCoordinator = appCoordinator
        self.reachabilityManager = reachabilityManager
        self.storage = storage
    }

    var api: NightscoutAPI? {
        apiProvider.api
    }

    func canUpload() -> Bool {
        guard appCoordinator.settings.value.isUploadEnabled,
              !NightscoutUploadPause.isPaused,
              reachabilityManager.isReachable
        else { return false }
        return apiProvider.api != nil
    }

    func makeGate(name: String, group: UploadScheduleGroup) -> UploadScheduleGate {
        UploadScheduleGate(
            name: name,
            group: group,
            appCoordinator: appCoordinator,
            reachabilityManager: reachabilityManager
        )
    }
}

enum NightscoutUploadPause {
    private static let pausedUntilKey = "nightscoutUpload.pausedUntil"

    static var pausedUntil: Date? {
        get { UserDefaults.standard.object(forKey: pausedUntilKey) as? Date }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: pausedUntilKey)
                return
            }
            UserDefaults.standard.set(newValue, forKey: pausedUntilKey)
        }
    }

    static var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > Date()
    }
}

final class UploadScheduleGate: Sendable {
    private let name: String
    private let group: UploadScheduleGroup
    private let appCoordinator: AppCoordinator
    private let reachabilityManager: ReachabilityManager

    init(
        name: String,
        group: UploadScheduleGroup,
        appCoordinator: AppCoordinator,
        reachabilityManager: ReachabilityManager
    ) {
        self.name = name
        self.group = group
        self.appCoordinator = appCoordinator
        self.reachabilityManager = reachabilityManager
    }

    func allows() async -> Bool {
        guard let network = currentNetworkSchedule() else {
            return true
        }
        switch network.interval {
        case .always:
            return true
        case .every12Hours,
             .everyHour,
             .never:
            if network.alwaysWhileCharging, await isCharging() {
                return true
            }
            guard let interval = network.interval.timeInterval else { return false }
            let elapsed = Date.now.timeIntervalSince(lastUpload ?? .distantPast)
            return elapsed >= interval
        }
    }

    var lastUpload: Date? {
        Self.lastUpload(named: name)
    }

    func recordUpload() {
        UserDefaults.standard.set(Date.now, forKey: Self.lastUploadKey(name))
    }

    static func lastUpload(named name: String) -> Date? {
        UserDefaults.standard.object(forKey: lastUploadKey(name)) as? Date
    }

    private static func lastUploadKey(_ name: String) -> String {
        "nightscoutUpload.lastUpload.\(name)"
    }

    private func currentNetworkSchedule() -> UploadNetworkSchedule? {
        let schedule = appCoordinator.settings.value[keyPath: group.scheduleKeyPath]
        switch reachabilityManager.status {
        case .reachable(.ethernetOrWiFi): return schedule.onWifi
        case .reachable(.cellular): return schedule.onCellular
        case .notReachable,
             .unknown: return nil
        }
    }

    private func isCharging() async -> Bool {
        let batteryState = await MainActor.run { UIDevice.current.batteryState }
        return batteryState == .charging || batteryState == .full
    }
}
