import Foundation
import SwiftDate
import Swinject

protocol AlertHistoryStorage: Sendable {
    func storeAlert(_ alerts: AlertEntry) async
    func syncDate() async -> Date
    func recentNotAck() async -> [AlertEntry]
    func deleteAlert(managerIdentifier: String, alertIdentifier: String) async
    func ackAlert(managerIdentifier: String, alertIdentifier: String, error: String?)
    func forceNotification()
}

final class BaseAlertHistoryStorage: AlertHistoryStorage {
    private let storage: FileStorage!
    private let appCoordinator: AppCoordinator!

    init(resolver: Resolver) {
        storage = resolver.resolve(FileStorage.self)!
        appCoordinator = resolver.resolve(AppCoordinator.self)!

        Task {
            let recent = await recentNotAck()
            self.appCoordinator.setAlertNotAck(recent.isNotEmpty)
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
        let uniqEvents: [AlertEntry] = await storage.appendAndModify([alert], to: file, uniqBy: \.issuedDate) {
            Self.filterOldAndSort($0)
        }
        let hasAlert = uniqEvents.contains { $0.acknowledgedDate == nil }
        appCoordinator.setAlertNotAck(hasAlert)
        appCoordinator.sendAlertUpdates(uniqEvents)
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recentNotAck() async -> [AlertEntry] {
        let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
        return Self.filterOldAndSort(alerts).filter { $0.acknowledgedDate == nil }
    }

    func ackAlert(managerIdentifier: String, alertIdentifier: String, error: String?) {
        Task {
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
                appCoordinator.setAlertNotAck(hasAlert)
            }
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
            appCoordinator.setAlertNotAck(hasAlert)
            appCoordinator.sendAlertUpdates(updatedValues)
        }
    }

    func forceNotification() {
        Task {
            let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
            let uniqEvents = Self.filterOldAndSort(alerts)
            let hasAlert = uniqEvents.contains { $0.acknowledgedDate == nil }
            appCoordinator.setAlertNotAck(hasAlert)
            appCoordinator.sendAlertUpdates(uniqEvents)
        }
    }
}
