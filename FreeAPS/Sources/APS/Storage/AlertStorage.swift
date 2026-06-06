import Foundation
import SwiftDate
import Swinject

// protocol AlertObserver {
//    func alertDidUpdate(_ alerts: [AlertEntry])
// }

protocol AlertHistoryStorage: Sendable {
    func storeAlert(_ alerts: AlertEntry) async
    func syncDate() async -> Date
    func recentNotAck() async -> [AlertEntry]
    func deleteAlert(managerIdentifier: String, alertIdentifier: String) async
    func ackAlert(managerIdentifier: String, alertIdentifier: String, error: String?) async
    func forceNotification() async

    // moved to appCoordinator
//    var alertNotAck: PassthroughSubject<Bool, Never> { get }
}

actor BaseAlertHistoryStorage: AlertHistoryStorage, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var appCoordinator: AppCoordinator!

    init(resolver: Resolver) {
        injectServices(resolver)
        Task {
            let recent = await recentNotAck()
            await self.appCoordinator.setAlertNotAck(recent.isNotEmpty)
        }
    }

    private static func filterOldAndSort(_ entries: [AlertEntry]) -> [AlertEntry] {
        let oneDayAgo = Date.now.addingTimeInterval(-1.days.timeInterval)
        return entries
            .filter { $0.issuedDate > oneDayAgo }
            .sorted { $0.issuedDate > $1.issuedDate }
    }

    func storeAlert(_ alert: AlertEntry) async {
        let file = OpenAPS.Monitor.alertHistory
        let uniqEvents: [AlertEntry] = await self.storage.appendAndModify([alert], to: file, uniqBy: \.issuedDate) {
            Self.filterOldAndSort($0)
        }
        let hasAlert = uniqEvents.contains { $0.acknowledgedDate == nil }
        await appCoordinator.setAlertNotAck(hasAlert)
        await appCoordinator.alertsUpdates.send(uniqEvents)
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recentNotAck() async -> [AlertEntry] {
        let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
        return Self.filterOldAndSort(alerts).filter { $0.acknowledgedDate == nil }
    }

    func ackAlert(managerIdentifier: String, alertIdentifier: String, error: String?) async {
        let (modified, updatedValues) = await storage
            .maybeModify(file: OpenAPS.Monitor.alertHistory, as: AlertEntry.self) { inStorage in
                var allValues = inStorage
                guard let entryIndex = allValues
                    .firstIndex(where: { $0.managerIdentifier == managerIdentifier && $0.alertIdentifier == alertIdentifier })
                else {
                    return nil // do not modify
                }
                if let error {
                    allValues[entryIndex].errorMessage = error
                } else {
                    allValues[entryIndex].acknowledgedDate = Date()
                }
                return Self.filterOldAndSort(allValues)
            }
        if modified {
            let hasAlert = updatedValues.contains { $0.acknowledgedDate == nil }
            await appCoordinator.setAlertNotAck(hasAlert)
        }
    }

    func deleteAlert(managerIdentifier: String, alertIdentifier: String) async {
        let (modified, updatedValues) = await storage
            .maybeModify(file: OpenAPS.Monitor.alertHistory, as: AlertEntry.self) { inStorage in
                var allValues = inStorage
                guard let entryIndex = allValues
                    .firstIndex(where: { $0.managerIdentifier == managerIdentifier && $0.alertIdentifier == alertIdentifier })
                else {
                    return nil // do not modify
                }
                allValues.remove(at: entryIndex)
                return Self.filterOldAndSort(allValues)
            }
        if modified {
            let hasAlert = updatedValues.contains { $0.acknowledgedDate == nil }
            await appCoordinator.setAlertNotAck(hasAlert)
            await appCoordinator.alertsUpdates.send(updatedValues)
        }
    }

    func forceNotification() async {
        let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
        let uniqEvents = Self.filterOldAndSort(alerts)
        let hasAlert = uniqEvents.contains { $0.acknowledgedDate == nil }
        await appCoordinator.setAlertNotAck(hasAlert)
        await appCoordinator.alertsUpdates.send(uniqEvents)
    }
}
