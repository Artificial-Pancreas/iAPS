import Foundation
import SwiftDate
import Swinject

protocol AlertHistoryStorage: Sendable {
    func storeIssuedAlert(_ alert: AlertEntry) async
    func markAlertDue(recordIdentifier: String, at date: Date) async -> AlertEntry?
    func alertsRequiringNotification() async -> [AlertEntry]
    func recordNotificationScheduling(recordIdentifier: String, error: String?) async
    func outstandingAlerts() async -> [AlertEntry]
    func retractAlert(managerIdentifier: String, alertIdentifier: String, at date: Date) async
    func retractAllAlerts(managerIdentifier: String, at date: Date) async -> [AlertIdentity]
    func ackAlerts(recordIdentifiers: [String], error: String?) async
}

final class BaseAlertHistoryStorage: AlertHistoryStorage {
    private let storage: FileStorage!
    private let appCoordinator: AppCoordinator!

    init(resolver: Resolver) {
        storage = resolver.resolve(FileStorage.self)!
        appCoordinator = resolver.resolve(AppCoordinator.self)!

        Task {
            let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
            updateAlertBadge(Self.filterOldAndSort(alerts))
        }
    }

    private static func filterOldAndSort(_ entries: [AlertEntry]) -> [AlertEntry] {
        let oldestHistoryDate = Date.now.subtractingTimeInterval(.days(90))
        return entries
            .filter { entry in
                if entry.isPending {
                    return true
                }
                return (entry.retractedDate ?? entry.firedDate ?? entry.issuedDate) > oldestHistoryDate
            }
            .sorted { $0.issuedDate > $1.issuedDate }
    }

    func storeIssuedAlert(_ alert: AlertEntry) async {
        let alerts: [AlertEntry] = await storage.modify(file: OpenAPS.Monitor.alertHistory, as: AlertEntry.self) { stored in
            var updated = stored.compactMap { existing -> AlertEntry? in
                let hasSameIdentifier = existing.managerIdentifier == alert.managerIdentifier &&
                    existing.alertIdentifier == alert.alertIdentifier
                if hasSameIdentifier, existing.isPending {
                    return nil
                }
                if hasSameIdentifier, existing.isRepeating, existing.retractedDate == nil {
                    var retracted = existing
                    retracted.retractedDate = alert.issuedDate
                    return retracted
                }
                return existing
            }
            if !updated.contains(where: { $0.storageIdentifier == alert.storageIdentifier }) {
                updated.append(alert)
            }
            return Self.filterOldAndSort(updated)
        }
        updateAlertBadge(alerts)
    }

    /// Stamps `firedDate` if this is the record's first occurrence. Returns the record either way: one
    /// already fired - a notification delivered before a restart, or tapped a second time - still needs
    /// bringing up.
    func markAlertDue(recordIdentifier: String, at date: Date) async -> AlertEntry? {
        let result: (Bool, [AlertEntry], data: AlertEntry?) = await storage
            .maybeModifyWithData(file: OpenAPS.Monitor.alertHistory, as: AlertEntry.self) { stored in
                var updated = stored
                guard let index = updated.firstIndex(where: { $0.storageIdentifier == recordIdentifier }),
                      updated[index].retractedDate == nil,
                      updated[index].firedDate == nil
                else {
                    return nil
                }
                updated[index].firedDate = date
                return (Self.filterOldAndSort(updated), data: updated[index])
            }
        let (modified, currentValues, dueAlert) = result
        if modified, let dueAlert {
            updateAlertBadge(currentValues)
            return dueAlert
        }
        // Nothing was written, which means either that the record is gone or retracted - nothing to
        // report - or that it had already fired, in which case the caller still needs it.
        guard let existing = currentValues.first(where: { $0.storageIdentifier == recordIdentifier }),
              existing.retractedDate == nil, existing.firedDate != nil
        else {
            return nil
        }
        return existing
    }

    func alertsRequiringNotification() async -> [AlertEntry] {
        let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
        return Self.filterOldAndSort(alerts).filter(\.requiresNotificationRequest)
    }

    func recordNotificationScheduling(recordIdentifier: String, error: String?) async {
        _ = await storage.maybeModify(file: OpenAPS.Monitor.alertHistory, as: AlertEntry.self) { stored in
            var updated = stored
            guard let index = updated.firstIndex(where: { $0.storageIdentifier == recordIdentifier }) else {
                return nil
            }
            updated[index].notificationScheduled = error == nil
            updated[index].notificationErrorMessage = error
            return Self.filterOldAndSort(updated)
        }
    }

    /// Everything that still needs showing to the user - what Loop replays at launch from
    /// `lookupAllUnacknowledgedUnretracted` plus `lookupAllAcknowledgedUnretractedRepeatingAlerts`.
    /// A repeating alert is included even once acknowledged: acknowledging clears the occurrence on
    /// screen, it does not end the alert, which runs until its issuer retracts it.
    func outstandingAlerts() async -> [AlertEntry] {
        let alerts = await storage.retrieve(OpenAPS.Monitor.alertHistory, as: [AlertEntry].self) ?? []
        return Self.filterOldAndSort(alerts)
            .filter { $0.isPresentable && ($0.acknowledgedDate == nil || $0.isRepeating) }
    }

    /// Acknowledges exactly the records named, and only while they are still outstanding.
    ///
    /// Record-scoped rather than identity-scoped on purpose. The same alert can be issued more than
    /// once before anyone acknowledges it - each issue is its own record - so the caller acknowledges
    /// every record that was outstanding when the user answered, which is what keeps earlier issues
    /// from staying outstanding forever (badge lit, replayed on every launch); Loop's
    /// `recordAcknowledgement` updates all matching unacknowledged records for the same reason. What
    /// it must *not* do is stamp a record the user never saw: a device can re-issue the same alert
    /// while the acknowledgement is still travelling to it (an Omnipod round trip takes seconds), and
    /// an identity-scoped write would silently acknowledge that new issue unseen.
    ///
    /// A device that could not be told is recorded as acknowledged all the same, as in Loop's
    /// `acknowledgeAlert`: acknowledging means the user has seen the alert, and a dead or out-of-range
    /// device would fail every retry while keeping the card coming back on every launch. The device's
    /// error is kept on the record as history; the device itself may keep alarming on its own until its
    /// next alert or until it reconnects.
    func ackAlerts(recordIdentifiers: [String], error: String?) async {
        guard recordIdentifiers.isNotEmpty else { return }
        let identifiers = Set(recordIdentifiers)
        let (modified, updatedValues) = await storage
            .maybeModify(file: OpenAPS.Monitor.alertHistory, as: AlertEntry.self) { inStorage in
                var allValues = inStorage
                let outstanding = allValues.indices.filter { index in
                    identifiers.contains(allValues[index].storageIdentifier) &&
                        allValues[index].isPresentable &&
                        allValues[index].acknowledgedDate == nil
                }
                guard outstanding.isNotEmpty else {
                    return nil // do not modify
                }
                let acknowledgedDate = Date()
                for index in outstanding {
                    if let error {
                        allValues[index].errorMessage = error
                    }
                    allValues[index].acknowledgedDate = acknowledgedDate
                }
                return Self.filterOldAndSort(allValues)
            }
        if modified {
            updateAlertBadge(updatedValues)
        }
    }

    /// Retracts *every* unretracted record the predicate matches, not just the newest. A device may
    /// issue the same identifier more than once before retracting it once (Minimed's low reservoir at
    /// 20 U, then 10 U), and a leftover record would stay outstanding - badge lit, replayed on every
    /// launch - for the whole retention period. This deliberately departs from Loop's latest-only
    /// `recordRetraction`.
    ///
    /// A pending record retracted before its scheduled date is dropped rather than stamped: it never
    /// showed, so it is not history.
    ///
    /// Returns the identities it touched (deduplicated), so a caller can take down the notification
    /// requests, timers and cards that belong to them.
    private func retract(
        where matches: @escaping @Sendable(AlertEntry) -> Bool,
        at date: Date
    ) async -> [AlertIdentity] {
        let (modified, updatedValues, retracted) = await storage
            .maybeModifyWithData(
                file: OpenAPS.Monitor.alertHistory,
                as: AlertEntry.self
            ) { inStorage -> ([AlertEntry], data: [AlertIdentity])? in
                var identities: [AlertIdentity] = []
                let allValues = inStorage.compactMap { existing -> AlertEntry? in
                    guard existing.retractedDate == nil, matches(existing) else {
                        return existing
                    }
                    if !identities.contains(existing.identity) {
                        identities.append(existing.identity)
                    }
                    if existing.isPending, let scheduledDate = existing.scheduledDate, scheduledDate >= date {
                        return nil // retracted before it ever showed
                    }
                    var retracted = existing
                    retracted.retractedDate = date
                    return retracted
                }
                guard identities.isNotEmpty else {
                    return nil // do not modify
                }
                return (Self.filterOldAndSort(allValues), data: identities)
            }
        if modified {
            updateAlertBadge(updatedValues)
        }
        return retracted ?? []
    }

    /// Retracts every unretracted record of one alert. See `retract(where:at:)` for the record handling.
    func retractAlert(managerIdentifier: String, alertIdentifier: String, at date: Date) async {
        _ = await retract(
            where: { $0.managerIdentifier == managerIdentifier && $0.alertIdentifier == alertIdentifier },
            at: date
        )
    }

    /// Retracts every unretracted record belonging to a device manager, whatever its alert identifier.
    /// For a device that has been removed or replaced: nothing will ever retract its alerts, and left
    /// alone a pending record is kept forever and a fired repeating one keeps being re-armed on every
    /// launch. See `retract(where:at:)` for the record handling and the returned identities.
    func retractAllAlerts(managerIdentifier: String, at date: Date) async -> [AlertIdentity] {
        await retract(where: { $0.managerIdentifier == managerIdentifier }, at: date)
    }

    /// The badge is the store's only outward signal. Putting alerts on screen and taking them off it
    /// belongs to `InAppAlertScheduler`, which owns that surface end to end.
    private func updateAlertBadge(_ alerts: [AlertEntry]) {
        appCoordinator.setAlertNotAck(alerts.contains { $0.isPresentable && $0.acknowledgedDate == nil })
    }
}
