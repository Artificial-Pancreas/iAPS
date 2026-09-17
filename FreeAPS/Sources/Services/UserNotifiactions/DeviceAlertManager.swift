import Foundation
import LoopKit
@preconcurrency import UserNotifications

enum DeviceAlertNotification {
    static let categoryIdentifier = "FreeAPS.deviceAlert"
    static let acknowledgeActionIdentifier = "FreeAPS.acknowledgeDeviceAlert"

    enum UserInfoKey: String {
        case recordIdentifier
        case managerIdentifier
        case alertIdentifier
        case hasForegroundContent
    }

    static func recordIdentifier(from content: UNNotificationContent) -> String? {
        content.userInfo[UserInfoKey.recordIdentifier.rawValue] as? String
    }

    static func hasForegroundContent(_ content: UNNotificationContent) -> Bool {
        content.userInfo[UserInfoKey.hasForegroundContent.rawValue] as? Bool ?? true
    }

    static func alertIdentity(from content: UNNotificationContent) -> AlertIdentity? {
        guard let managerIdentifier = content.userInfo[UserInfoKey.managerIdentifier.rawValue] as? String,
              let alertIdentifier = content.userInfo[UserInfoKey.alertIdentifier.rawValue] as? String
        else {
            return nil
        }
        return AlertIdentity(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier)
    }
}

protocol DeviceAlertManager: Sendable {
    func issueAlert(_ alert: Alert)
    func retractAlert(identifier: Alert.Identifier)
    /// Retracts everything a device manager still has outstanding. For a device that has been removed
    /// or replaced - it will never retract its own alerts again - and for the user's escape hatch out
    /// of a card that cannot be acknowledged.
    func retractAllAlerts(managerIdentifier: String)

    /// A notification is about to be shown while the app is in the foreground.
    func notificationWillPresent(recordIdentifier: String)
    /// The user tapped the notification itself, opening the app.
    func notificationWasOpened(recordIdentifier: String)
    /// The user answered an alert. Records it and clears the surfaces, whether or not the device could
    /// be told - `failure` only adds a card saying the device still has it.
    /// Reached through `DeviceDataManager.acknowledgeDeviceAlert`, which is what talks to the device and
    /// captures `recordIdentifiers` - the records outstanding when the user answered - before it does.
    func alertWasAcknowledged(
        _ identity: AlertIdentity,
        recordIdentifiers: [String],
        recordIdentifier: String?,
        failure: String?
    ) async

    /// The in-app card for this alert has just been taken off the screen by the user's own tap, before
    /// anything else about the acknowledgement has happened. Only tells the scheduler the card is gone -
    /// nothing is recorded, and no dismissal is sent back to the UI, which is already rid of it.
    ///
    /// Without it the scheduler would go on believing a card is up for the whole device round trip, and
    /// an identical re-issue arriving in that window would be folded into the invisible one and never
    /// shown.
    func alertCardDismissed(_ identity: AlertIdentity)

    func outstandingAlerts() async -> [AlertEntry]
}

actor BaseDeviceAlertManager: DeviceAlertManager, AppService, LifetimeOwner {
    private enum AlertOperation: Sendable {
        case issue(AlertEntry)
        case retract(identity: AlertIdentity, date: Date)
        /// Every alert of one device manager, for a device that is gone.
        case retractAll(managerIdentifier: String, date: Date)
        /// A foreground timer reached an occurrence.
        case occurrence(recordIdentifier: String, date: Date)
        /// A notification became due, or was opened. `includeRepeating` is set only for an explicit
        /// tap - automatic foreground delivery leaves a repeating alert's card to its timer.
        case notificationDue(recordIdentifier: String, includeRepeating: Bool)
        /// The device has answered an acknowledgement, for the records that were outstanding when the
        /// user answered. Everything the acknowledgement does - the storage write, the delivered
        /// notification, the card - happens here, so none of it can interleave with an issue of the
        /// same alert. `done` is resumed once all of that has been done, so the caller - a notification
        /// action holding a background task, which the system may suspend the moment it returns - can
        /// wait for the work rather than just for it to be queued.
        case acknowledged(
            identity: AlertIdentity,
            recordIdentifiers: [String],
            failure: String?,
            done: CheckedContinuation<Void, Never>
        )
        /// The user's tap has already taken an alert's card off the screen; the scheduler has yet to
        /// hear of it. Queued like everything else that touches the scheduler, so it stays ordered
        /// against the presentations around it.
        case cardDismissed(identity: AlertIdentity)
        case reconcile
        case replayOutstanding
    }

    private let alertHistoryStorage: AlertHistoryStorage
    private let appCoordinator: AppCoordinator
    private let center: UNUserNotificationCenter
    private let inApp: InAppAlertScheduler

    let lifetime = Lifetime()

    // Alerts arrive from device-manager queues that cannot await an actor, so `issueAlert` and
    // `retractAlert` stay nonisolated and hand the work over through this stream. `yield` is
    // synchronous and the stream preserves order, which a `Task` per call would not: a device that
    // issues an alert and immediately retracts it must not have the two land the other way round.
    // Buffering is unbounded, so anything issued while the pump/CGM managers are still coming up waits
    // for `start()` to begin consuming rather than being dropped.
    //
    // The *device* half of an acknowledgement deliberately does not go through here: running a pump
    // round-trip inside the queue would stall every issue and retraction behind it for as long as the
    // device takes to answer, and a notification action has to be awaitable end to end - it runs with
    // the app in the background, where returning early invites suspension. Everything the
    // acknowledgement then changes on this side - the storage stamp, the delivered notification, the
    // card - is queued as one operation, because the alert it answers can be re-issued while the device
    // is still being told.
    private let operations: AsyncStream<AlertOperation>
    private let operationsContinuation: AsyncStream<AlertOperation>.Continuation

    private var started = false
    private var replayedOutstandingAlerts = false

    init(
        alertHistoryStorage: AlertHistoryStorage,
        appCoordinator: AppCoordinator,
        center: UNUserNotificationCenter = .current()
    ) {
        self.alertHistoryStorage = alertHistoryStorage
        self.appCoordinator = appCoordinator
        self.center = center

        let (stream, continuation) = AsyncStream.makeStream(of: AlertOperation.self)
        operations = stream
        operationsContinuation = continuation
        // The scheduler reports an occurrence rather than acting on the record itself, so the
        // record-keeping stays ordered against issues and retractions like everything else.
        inApp = InAppAlertScheduler(appCoordinator: appCoordinator) { recordIdentifier in
            continuation.yield(.occurrence(recordIdentifier: recordIdentifier, date: Date()))
        }
    }

    func start() async {
        guard !started else { return }
        started = true

        // Reconcile before consuming, so a notification that fired while the app was down is
        // promoted from the store first and an alert re-issued on startup finds the record already
        // marked as fired. Safe to call directly: the queue is not being drained yet, and every
        // queued entry point only enqueues.
        await reconcilePendingAlerts()

        // Runs for the life of the app: the manager is a singleton app service, and the loop holds
        // it for as long as it is iterating, so there is nothing to tear down.
        Task { await consumeOperations() }

        // Queued rather than called directly. Reconciliation reads the store and then reschedules,
        // and an issue or retract suspended between its own two steps would otherwise let it act on
        // a record that is about to be retracted or superseded - and put back a notification that
        // had just been cancelled.
        observe(appCoordinator.appBecomeActiveEvents) { manager, _ in
            manager.scheduleReconciliation()
        }

        observe(appCoordinator.alertPresentationReady.filter { $0 }) { manager, _ in
            manager.scheduleReplay()
        }
    }

    // MARK: - AlertIssuer

    nonisolated func issueAlert(_ alert: Alert) {
        operationsContinuation.yield(.issue(AlertEntry(from: alert)))
    }

    nonisolated func retractAlert(identifier: Alert.Identifier) {
        operationsContinuation.yield(
            .retract(
                identity: AlertIdentity(
                    managerIdentifier: identifier.managerIdentifier,
                    alertIdentifier: identifier.alertIdentifier
                ),
                date: Date()
            )
        )
    }

    /// Queued like `retractAlert`, and for the same reason: every scheduler mutation is ordered against
    /// the issues and presentations around it. Reached when a pump or CGM manager is removed or
    /// replaced, and from the card's long-press escape hatch.
    nonisolated func retractAllAlerts(managerIdentifier: String) {
        operationsContinuation.yield(.retractAll(managerIdentifier: managerIdentifier, date: Date()))
    }

    // There is deliberately no hook for the *device* acknowledging an alert. An alert is answered here
    // only by a user gesture - the card's button, the notification's action, "Acknowledge all alerts" -
    // and that gesture is the only thing that says anyone has seen it. Anything else clearing an alert
    // (a device that stops repeating it, a plugin that responds on its own) must leave the surfaces
    // alone: dropping the delivered notification would take a pod fault out of Notification Centre
    // before the user could look at it, and dropping the pending one would end a repeating alert after
    // a single fire. A repeating alert stops when its issuer retracts it, and only then.

    // MARK: - Notification routes

    /// Automatic foreground delivery. A repeating alert's card is left to its timer, which is the one
    /// clock for those: iOS keeps the phase its repeating trigger was armed with and a re-added request
    /// restarts that phase, so letting both drive presentation stacks up cards at irregular intervals.
    ///
    /// Queued, like every other thing that puts a card up. Done inline it would suspend on the store
    /// and could resume to present a record that a retraction had taken down while it waited.
    nonisolated func notificationWillPresent(recordIdentifier: String) {
        operationsContinuation.yield(.notificationDue(recordIdentifier: recordIdentifier, includeRepeating: false))
    }

    /// The user tapped the notification. An explicit request to see the alert, so it is shown whatever
    /// its trigger - the scheduler drops it only if that alert's card is already up.
    nonisolated func notificationWasOpened(recordIdentifier: String) {
        operationsContinuation.yield(.notificationDue(recordIdentifier: recordIdentifier, includeRepeating: true))
    }

    // MARK: - Acknowledgement

    /// The device has been told; this is the record and the cleanup. `recordIdentifiers` are the records
    /// that were outstanding for this alert when the user answered, captured by the caller before the
    /// device round trip: everything here is scoped to those, so an issue of the same alert arriving
    /// while the device was being told is neither acknowledged unseen nor taken off the screen.
    /// `recordIdentifier` is passed when the acknowledgement came from a notification, and is stamped
    /// due first: one delivered while the app was backgrounded or terminated has no `firedDate`, and
    /// acknowledging first would find no outstanding record and do nothing.
    ///
    /// A failure changes nothing here beyond the card it puts up and the line it logs, as in Loop's
    /// `acknowledgeAlert`: the acknowledgement is recorded, the notification removed and the card taken
    /// down regardless. Acknowledging means the user has seen the alert - a device that could not be
    /// told may keep alarming on its own until its next alert or until it reconnects (Omnipod's
    /// `silenceAcknowledgedAlerts` clears it once the pod is back in range), and the card's long-press
    /// "dismiss all alerts from this device" menu is the emergency exit for a device that is gone.
    /// `failure` is the device's error already rendered to text: `Error` is not `Sendable`, and this is
    /// the only thing anything downstream does with it.
    func alertWasAcknowledged(
        _ identity: AlertIdentity,
        recordIdentifiers: [String],
        recordIdentifier: String?,
        failure: String?
    ) async {
        if let recordIdentifier {
            // Nothing is presented on the way through - the user has just answered this very alert.
            await markDue(recordIdentifier: recordIdentifier)
        }

        // Queued, so that the whole acknowledgement - store, notification centre and card - stays
        // ordered against issues, retractions and presentations. Done inline it would interleave with
        // an issue of the same alert: the new record could be stored between the stamp and the
        // dismissal, be shown, and then be taken down by it.
        //
        // Awaited rather than fire-and-forget: the caller of an acknowledgement from a notification
        // action ends its background task and calls the UN completion handler as soon as this returns,
        // and the system may suspend the app right there - with the storage write, the notification
        // removal and the card still sitting in the queue. The continuation is resumed by the operation
        // handler once all of that is done, and by the `else` below if the stream could not take the
        // operation, so it is resumed exactly once on every path.
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let yielded = operationsContinuation.yield(
                .acknowledged(
                    identity: identity,
                    recordIdentifiers: recordIdentifiers,
                    failure: failure,
                    done: done
                )
            )
            if case .enqueued = yielded {
                // The handler owns the continuation now.
            } else {
                // Unreachable as things stand - the buffer is unbounded, so nothing is ever dropped,
                // and the stream is never finished: the manager is a singleton app service that lives
                // for the life of the app, and nothing calls `finish()`. Handled anyway, because a
                // continuation that is never resumed would leave this caller suspended forever.
                done.resume()
            }
        }
    }

    /// Yielded rather than awaited: the card is already off the screen, and the caller is the main actor
    /// in the middle of a tap handler. The operation only has to reach the scheduler before the
    /// acknowledgement that follows it, which the queue's ordering guarantees.
    nonisolated func alertCardDismissed(_ identity: AlertIdentity) {
        operationsContinuation.yield(.cardDismissed(identity: identity))
    }

    func outstandingAlerts() async -> [AlertEntry] {
        await alertHistoryStorage.outstandingAlerts()
    }

    // MARK: - Operation queue

    private nonisolated func scheduleReconciliation() {
        operationsContinuation.yield(.reconcile)
    }

    private nonisolated func scheduleReplay() {
        operationsContinuation.yield(.replayOutstanding)
    }

    private func consumeOperations() async {
        for await operation in operations {
            await perform(operation)
        }
    }

    private func perform(_ operation: AlertOperation) async {
        switch operation {
        case let .issue(entry):
            await issue(entry)
        case let .retract(identity, date):
            await retract(identity, at: date)
        case let .retractAll(managerIdentifier, date):
            await retractAll(managerIdentifier: managerIdentifier, at: date)
        case let .occurrence(recordIdentifier, date):
            // Presenting the record read back from the store, never the entry the timer was scheduled
            // with: that copy still has `firedDate == nil` and is not presentable, and it can no
            // longer be true - the alert may have been acknowledged or retracted since.
            if let due = await markDue(recordIdentifier: recordIdentifier, at: date) {
                await inApp.showAlert(due)
            }
        case let .notificationDue(recordIdentifier, includeRepeating):
            guard let due = await markDue(recordIdentifier: recordIdentifier) else { break }
            guard includeRepeating || !due.isRepeating else { break }
            await inApp.showAlert(due)
        case let .acknowledged(identity, recordIdentifiers, failure, done):
            // The one exit of this case, taken whatever happens in between, so the waiting caller is
            // released exactly once and only after every part of the acknowledgement has been done.
            defer { done.resume() }
            let outcome = failure
                .map { "could not be cleared on the device - \($0), acknowledged locally anyway" } ?? "acknowledged"
            debug(
                .deviceManager,
                "Device alert \(outcome) [\(identity.managerIdentifier)/\(identity.alertIdentifier)]"
            )
            await alertHistoryStorage.ackAlerts(recordIdentifiers: recordIdentifiers, error: failure)
            // Record-scoped, like the storage ack and the card dismissal above and below it. iOS keeps
            // one delivered notification per request identifier, and every record of an alert shares
            // that identifier, so the banner on screen is whichever record was delivered last - which
            // may be a newer re-issue that arrived while this acknowledgement was in flight to the
            // device. Removing by identity alone would take that newer banner down unanswered.
            await removeDeliveredNotification(for: identity, ifOwnedBy: Set(recordIdentifiers))
            await inApp.alertWasAcknowledged(identity, recordIdentifiers: recordIdentifiers)
            if let failure {
                // The alert counts as answered - the record is stamped and the card is down - but the
                // device was never told, and may keep alarming on its own until its next alert or until
                // it reconnects. Say so, rather than let it look fully cleared. Loop puts up its own
                // `presentAcknowledgementFailedAlert` in the same place.
                appCoordinator.sendAlertMessage(
                    MessageContent(
                        content: String(
                            format: NSLocalizedString(
                                "Unable to clear the alert from your device: %@",
                                comment: "Message shown when acknowledging a device alert fails"
                            ),
                            failure
                        ),
                        type: .warning
                    )
                )
            }
        case let .cardDismissed(identity):
            await inApp.cardWentDown(identity)
        case .reconcile:
            await reconcilePendingAlerts()
        case .replayOutstanding:
            await replayOutstandingAlertsIfNeeded()
        }
    }

    private func issue(_ alert: AlertEntry) async {
        // Device alerts (pod faults, expiry, occlusion, CGM alarms) otherwise never reach the log
        // files - only the alert-history storage, which is not in a log bundle. Every issued alert
        // passes through here, so this is the one place that guarantees the record.
        debug(
            .deviceManager,
            "Device alert [\(alert.managerIdentifier)/\(alert.alertIdentifier)]: \(alert.summary)"
        )

        await alertHistoryStorage.storeIssuedAlert(alert)
        await inApp.scheduleAlert(alert, replacingExisting: true)

        if alert.isPending {
            await scheduleNotification(for: alert)
        } else {
            await addNotificationRequest(for: alert, trigger: nil)
        }
    }

    private func retract(_ identity: AlertIdentity, at date: Date) async {
        debug(.deviceManager, "Device alert retracted [\(identity.managerIdentifier)/\(identity.alertIdentifier)]")

        await takeDown(identity)

        await alertHistoryStorage.retractAlert(
            managerIdentifier: identity.managerIdentifier,
            alertIdentifier: identity.alertIdentifier,
            at: date
        )
    }

    /// Retracts every outstanding record of one device manager and takes down everything they own: the
    /// pending and delivered notifications, the in-app timers, and any card on screen. The store is
    /// asked first because it is the one that knows which records are still unretracted; it answers
    /// with their identities, which is what the surfaces are keyed by.
    private func retractAll(managerIdentifier: String, at date: Date) async {
        let identities = await alertHistoryStorage.retractAllAlerts(managerIdentifier: managerIdentifier, at: date)
        guard identities.isNotEmpty else { return }

        warning(
            .deviceManager,
            "Retracting \(identities.count) device alert(s) of [\(managerIdentifier)]: \(identities.map(\.alertIdentifier).joined(separator: ", "))"
        )

        for identity in identities {
            await inApp.unscheduleAlert(identity)
        }
        // One round-trip to the notification centre for the whole set rather than one per identity.
        let notificationIdentifiers = identities.map(\.notificationIdentifier)
        center.removePendingNotificationRequests(withIdentifiers: notificationIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: notificationIdentifiers)
    }

    /// Everything one retracted alert owns: its in-app timer, its card, and its notification requests,
    /// pending and delivered. The condition is gone, so the scheduled repeats and anything already on
    /// screen go with it.
    private func takeDown(_ identity: AlertIdentity) async {
        await inApp.unscheduleAlert(identity)
        let notificationIdentifier = identity.notificationIdentifier
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    /// Takes down the delivered notification of `identity` only if the one iOS is holding belongs to
    /// one of `recordIdentifiers` - the records that were acknowledged. A device that re-issues while
    /// an acknowledgement is on its way to it replaces the delivered notification in place (same
    /// request identifier, newer record), and that newer banner has not been answered.
    ///
    /// A delivered notification without a record identifier in its `userInfo` - a request built by an
    /// older version of the app, still delivered across the upgrade - is removed: it cannot be newer
    /// than this acknowledgement, and leaving it on screen would leave a banner nothing can clear.
    private func removeDeliveredNotification(for identity: AlertIdentity, ifOwnedBy recordIdentifiers: Set<String>) async {
        let notificationIdentifier = identity.notificationIdentifier
        let delivered = await center.deliveredNotifications()
        guard let notification = delivered.first(where: { $0.request.identifier == notificationIdentifier }) else {
            return
        }
        if let recordIdentifier = DeviceAlertNotification.recordIdentifier(from: notification.request.content),
           !recordIdentifiers.contains(recordIdentifier)
        {
            return
        }
        center.removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    /// Stamps `firedDate` if this is the record's first occurrence. Returns the record either way: a
    /// notification tapped a second time, or one delivered before a restart, still needs its alert
    /// brought up.
    @discardableResult private func markDue(recordIdentifier: String, at date: Date = Date()) async -> AlertEntry? {
        await alertHistoryStorage.markAlertDue(recordIdentifier: recordIdentifier, at: date)
    }

    // MARK: - Startup

    private func reconcilePendingAlerts() async {
        let notificationAlerts = await alertHistoryStorage.alertsRequiringNotification()
        guard notificationAlerts.isNotEmpty else { return }

        let requests = await center.pendingNotificationRequests()
        let requestRecords = Dictionary(uniqueKeysWithValues: requests.compactMap { request -> (String, String)? in
            guard let recordIdentifier = DeviceAlertNotification.recordIdentifier(from: request.content) else {
                return nil
            }
            return (request.identifier, recordIdentifier)
        })
        let now = Date()

        for alert in notificationAlerts {
            guard let scheduledDate = alert.scheduledDate else { continue }
            var reconciledAlert = alert
            if alert.isPending, scheduledDate <= now {
                // The alert came due while the app was down. iOS delivered the notification on its own
                // if one was ever scheduled; if none was - killed between storing the record and
                // adding the request, or the request was rejected - nothing was ever shown, so post it
                // now rather than let the alert disappear. A repeating one needs no help here: its
                // request is (re)armed below.
                if !alert.isRepeating, alert.notificationScheduled != true {
                    await addNotificationRequest(for: alert, trigger: nil)
                }
                if let due = await markDue(recordIdentifier: alert.storageIdentifier, at: scheduledDate) {
                    reconciledAlert = due
                    await inApp.showAlert(due)
                }
            }
            if reconciledAlert.requiresNotificationRequest {
                // Timers do not survive a restart, and neither does a suspended app's clock, so this
                // is where they come back. Existing ones are left alone.
                await inApp.scheduleAlert(reconciledAlert, replacingExisting: false)

                if requestRecords[reconciledAlert.notificationIdentifier] != reconciledAlert.storageIdentifier {
                    await scheduleNotification(for: reconciledAlert)
                }
            }
        }
    }

    /// Loop replays its outstanding alerts once per launch (`playbackAlertsFromPersistence`). Without
    /// it an unacknowledged alert loses its in-app presentation across a restart, and with it the only
    /// place left to acknowledge it from. Driven by `alertPresentationReady` rather than by `start()`
    /// or by scene activation: at `start()` the UI has not subscribed to the presentation bus yet, and
    /// `onChange(of: scenePhase)` does not fire for the `.active` the app launches into.
    ///
    /// An acknowledged repeating alert is not shown again here - the user has answered the occurrence
    /// that was on screen. It only needs its next occurrence re-armed, which `reconcilePendingAlerts`
    /// already does through `inApp.scheduleAlert(_, replacingExisting: false)`.
    private func replayOutstandingAlertsIfNeeded() async {
        guard !replayedOutstandingAlerts else { return }
        replayedOutstandingAlerts = true
        await inApp.allowPresentation()
        // Only the newest record per alert. Several unacknowledged records of one alert are the normal
        // case for a device that re-issues as its condition worsens (Minimed's low reservoir at 20 U,
        // then 10 U), and `showAlert` replaces a card whenever the text differs - so replaying all of
        // them in the store's newest-first order would end with the oldest, stalest text on screen.
        var replayed: Set<AlertIdentity> = []
        for alert in await alertHistoryStorage.outstandingAlerts() where alert.acknowledgedDate == nil {
            guard replayed.insert(alert.identity).inserted else { continue }
            await inApp.showAlert(alert)
        }
    }

    // MARK: - System notifications

    private func scheduleNotification(for alert: AlertEntry) async {
        guard let scheduledDate = alert.scheduledDate else { return }

        if alert.isRepeating {
            // Always a repeating system trigger, so iOS delivers every occurrence by itself. Nothing
            // here may depend on the app being alive to arm the next one: a repeating alert is exactly
            // the case where the app is likely backgrounded or terminated between fires, and
            // `willPresent` would never be called to do it.
            //
            // The period comes from the trigger, never from the time left until `scheduledDate`. A
            // `UNTimeIntervalNotificationTrigger` uses one interval for both the first fire and every
            // one after it, so using a remainder would turn a 30-minute reminder restored with two
            // minutes left into a two-minute nag. The cost is that the first fire after a restore can
            // slip by up to one period - the same trade-off Loop makes, described in the `storedType`
            // 2 comment in AlertEntry.swift.
            // Clamped again for records stored before `AlertEntry` clamped on the way in.
            let period = max(alert.storedTriggerInterval ?? AlertEntry.minimumRepeatInterval, AlertEntry.minimumRepeatInterval)
            await addNotificationRequest(
                for: alert,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: period, repeats: true)
            )
            return
        }

        let interval = scheduledDate.timeIntervalSinceNow
        guard interval > 0 else {
            // The delay ran out before this got scheduled. Loop collapses an elapsed `.delayed`
            // trigger to `.immediate` rather than dropping the alert, so post it now.
            await addNotificationRequest(for: alert, trigger: nil)
            if let due = await markDue(recordIdentifier: alert.storageIdentifier, at: scheduledDate) {
                await inApp.showAlert(due)
            }
            return
        }
        await addNotificationRequest(
            for: alert,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(interval, 1), repeats: false)
        )
    }

    private func addNotificationRequest(for alert: AlertEntry, trigger: UNNotificationTrigger?) async {
        let request = UNNotificationRequest(
            identifier: alert.notificationIdentifier,
            content: notificationContent(for: alert),
            trigger: trigger
        )

        do {
            try await center.add(request)
            await alertHistoryStorage.recordNotificationScheduling(recordIdentifier: alert.storageIdentifier, error: nil)
            debug(.deviceManager, "Scheduled device alert [\(alert.notificationIdentifier)]")
        } catch {
            await alertHistoryStorage.recordNotificationScheduling(
                recordIdentifier: alert.storageIdentifier,
                error: error.localizedDescription
            )
            warning(.deviceManager, "Unable to schedule device alert [\(alert.notificationIdentifier)]", error: error)
        }
    }

    private func notificationContent(for alert: AlertEntry) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alert.backgroundContentTitle ?? alert.contentTitle ?? "Device alert"
        content.body = alert.backgroundContentBody ?? alert.contentBody ?? ""
        content.categoryIdentifier = DeviceAlertNotification.categoryIdentifier
        content.threadIdentifier = alert.notificationIdentifier
        content.interruptionLevel = alert.interruptionLevel.unNotificationInterruptionLevel
        content.userInfo = [
            DeviceAlertNotification.UserInfoKey.recordIdentifier.rawValue: alert.storageIdentifier,
            DeviceAlertNotification.UserInfoKey.managerIdentifier.rawValue: alert.managerIdentifier,
            DeviceAlertNotification.UserInfoKey.alertIdentifier.rawValue: alert.alertIdentifier,
            DeviceAlertNotification.UserInfoKey.hasForegroundContent.rawValue: alert.hasForegroundContent
        ]

        // Only two of the sounds Loop distinguishes can actually happen here, so the rest are left
        // out rather than left looking functional:
        //  - `alert.soundName` is recorded on the entry but never played. A named sound has to exist
        //    in the bundle or in Library/Sounds, which means running Loop's sound-vendor copy
        //    (`addAlertSoundVendor`/`initializeSoundVendor`) first. Nothing here does, and no plugin
        //    in the tree vends a sound anyway - every `getSounds()` returns [].
        //  - critical sounds (`.defaultCritical`, `.criticalSoundNamed`) need the
        //    com.apple.developer.usernotifications.critical-alerts entitlement, which iAPS does not
        //    ship and does not request in `requestAuthorization`. Asking for one regardless would
        //    quietly degrade to an ordinary sound while reading as though critical alerts worked.
        //    The interruption level is still set above, so a build that ever gains the entitlement
        //    gets the right treatment without a change here.
        content.sound = alert.soundIsVibrate == true ? nil : .default
        return content
    }
}

/// Everything the user sees in-app for a device alert: when a delayed or repeating one is due, whether
/// its card is up, and taking it down again.
actor InAppAlertScheduler {
    private let appCoordinator: AppCoordinator
    /// Called when a timer reaches an occurrence, with the record it belongs to. The caller stamps the
    /// record and calls back into `showAlert` with the current copy of it.
    private let reportOccurrence: @Sendable(String) -> Void

    private var pending: [AlertIdentity: PendingTimer] = [:]
    /// The alerts whose card is up, with the text each one was put up with. Keyed by identity rather
    /// than by record: a device re-issues the same alert identifier as its condition changes, and the
    /// card belongs to the alert, not to the issue of it.
    private var presented: [AlertIdentity: PresentedContent] = [:]
    private var nextToken: UInt64 = 0
    private var canPresent = false

    /// What the card is made of, and which record put it there. The text is compared so that a re-issue
    /// carrying new text replaces the card while an identical one - a repeat, a replay, a notification
    /// tapped twice - leaves it alone rather than flickering it. Only the foreground content is here:
    /// that is what the card renders, and the background content reaches the notification instead,
    /// which iOS already replaces in place.
    ///
    /// `storageIdentifier` takes no part in that comparison - it says nothing about what is on screen -
    /// but it is what an acknowledgement checks before taking the card down, so that one answering an
    /// earlier issue leaves a newer issue's card alone.
    private struct PresentedContent {
        let storageIdentifier: String
        let title: String?
        let body: String?
        let acknowledgeButtonLabel: String?

        init(_ alert: AlertEntry) {
            storageIdentifier = alert.storageIdentifier
            title = alert.contentTitle
            body = alert.contentBody
            acknowledgeButtonLabel = alert.acknowledgeButtonLabel
        }

        func rendersSameAs(_ other: PresentedContent) -> Bool {
            title == other.title && body == other.body && acknowledgeButtonLabel == other.acknowledgeButtonLabel
        }
    }

    private struct PendingTimer {
        /// Distinguishes this timer from a replacement scheduled for the same alert, so one that
        /// finishes just as it is superseded cannot clear the entry belonging to its successor.
        let token: UInt64
        let task: Task<Void, Never>
    }

    init(appCoordinator: AppCoordinator, reportOccurrence: @escaping @Sendable(String) -> Void) {
        self.appCoordinator = appCoordinator
        self.reportOccurrence = reportOccurrence
    }

    /// Presentation on our own clock, independent of the notification system - Loop schedules its
    /// modal on a `Timer` for the same reason. Without it a delayed or repeating alert has no in-app
    /// presence at all when notifications are denied or `center.add` failed: nothing would mark the
    /// alert due while the app stays in the foreground, since reconciliation only runs at launch and
    /// on scene activation, and a sensor-expiry warning would pass its deadline in silence.
    ///
    /// `replacingExisting` is true when the alert is being issued - that supersedes whatever was
    /// timing the previous issue of it - and false when reconciliation is putting timers back after a
    /// restart, where an already-running one is the good copy.
    func scheduleAlert(_ alert: AlertEntry, replacingExisting: Bool) {
        // Same guard as Loop's `schedule(alert:interval:repeats:)`: nothing to show, nothing to time.
        guard alert.contentBody != nil else { return }
        // `.immediate` shows now and has nothing to time, the same split Loop's `scheduleAlert` makes.
        guard alert.isPending || alert.isRepeating, let scheduledDate = alert.scheduledDate else {
            showAlert(alert)
            return
        }

        let identity = alert.identity
        if replacingExisting {
            cancelTimer(for: identity)
        } else if pending[identity] != nil {
            return
        }

        nextToken += 1
        let token = nextToken
        // A repeating alert re-arms itself forever; only a retraction stops it.
        let period: TimeInterval? = alert.isRepeating
            ? max(alert.storedTriggerInterval ?? AlertEntry.minimumRepeatInterval, AlertEntry.minimumRepeatInterval)
            : nil
        let firstOccurrence = Self.nextOccurrence(after: Date(), scheduledDate: scheduledDate, period: period)

        let task = Task { [weak self] in
            var delay = max(0, firstOccurrence.timeIntervalSinceNow)
            while true {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return // cancelled
                }
                await self?.timerReachedOccurrence(alert)
                guard let period else { break }
                delay = period
            }
            await self?.clearTimer(for: identity, token: token)
        }
        pending[identity] = PendingTimer(token: token, task: task)
    }

    /// Puts the alert on screen, if it is eligible and not already up. The single place that decides
    /// this: every route - a new alert, a timer occurrence, a notification, the launch replay - comes
    /// through here.
    func showAlert(_ alert: AlertEntry) {
        // Before the UI is listening a card would go nowhere, and marking it presented would stop the
        // launch replay from putting it up. Reconciliation runs at `start()`, ahead of that, and can
        // bring a delayed alert due; the replay reads the store afterwards and covers it.
        guard canPresent else { return }
        guard alert.isPresentable, let body = alert.contentBody else { return }
        // Acknowledging a repeating alert answers the occurrence on screen, not the alert - it runs
        // until its issuer retracts it - so later occurrences must still be shown. Loop keeps its
        // repeating modal timer running past acknowledgement for the same reason. Omnipod's
        // suspend-expired reminder is the case that needs it: it repeats until delivery resumes.
        guard alert.acknowledgedDate == nil || alert.isRepeating else { return }

        // A card already up for this alert is only worth disturbing if the device has something new to
        // say. MinimedPumpManager is the case: it re-issues `pumpReservoirLow` at each threshold with a
        // new body ("20 U left", then "10 U left") and no retraction in between, so dropping the second
        // one leaves the user reading the first. The UI replaces the card in place; the identity stays
        // presented throughout, so nothing takes the replacement back down with it.
        //
        // "Already up" is the truth here because the UI reports a card it has taken down itself the
        // moment it does (`cardWentDown`), rather than leaving it to the acknowledgement that follows
        // seconds later: an identical re-issue arriving in that window finds nothing presented and gets
        // a card of its own.
        let content = PresentedContent(alert)
        if let current = presented[alert.identity], current.rendersSameAs(content) {
            // Nothing new to show, but the card now stands for this record too: it is the newest issue
            // of the alert, so an acknowledgement of an earlier one must not take it down.
            presented[alert.identity] = content
            return
        }
        presented[alert.identity] = content

        let alertUp = alert.alertIdentifier.uppercased()
        let type: MessageType = alertUp.contains("FAULT") || alertUp.contains("ERROR") ? .errorPump : .warning
        appCoordinator.sendAlertMessage(
            MessageContent(
                content: body,
                type: type,
                alertIdentity: alert.identity,
                acknowledgeButtonLabel: alert.acknowledgeButtonLabel
            )
        )
    }

    /// The UI is subscribed; cards can go up from here on.
    func allowPresentation() {
        canPresent = true
    }

    /// The condition is gone: the timer stops and the card goes.
    func unscheduleAlert(_ identity: AlertIdentity) {
        cancelTimer(for: identity)
        dismiss(identity)
    }

    /// The user answered this occurrence. The card goes if it belongs to one of the records that were
    /// acknowledged - including when the store had nothing left to change, as for a repeating alert,
    /// which keeps one record, already stamped by the first acknowledgement.
    ///
    /// This is the route for an acknowledgement made somewhere other than the card - a notification
    /// action, or "Acknowledge all alerts" - while a card is up. An acknowledgement from the card itself
    /// normally finds nothing left to do: the UI reports that card down through `cardWentDown` as soon
    /// as it hides it, well before the device answers.
    ///
    /// What it does not do is take down a card belonging to a newer issue of the same alert: a device
    /// can re-issue while the acknowledgement is still travelling to it, and that card has not been
    /// answered. A repeating alert's timer keeps running either way, exactly as Loop leaves its pending
    /// modal timer alone on acknowledgement - acknowledging answers the occurrence, not the alert,
    /// which runs until its issuer retracts it.
    func alertWasAcknowledged(_ identity: AlertIdentity, recordIdentifiers: [String]) {
        guard let current = presented[identity] else { return }
        guard recordIdentifiers.contains(current.storageIdentifier) else { return }
        dismiss(identity)
    }

    /// The card is off the screen already - the user's tap took it down there and then. Only the
    /// scheduler's own record of it is cleared; unlike `dismiss` nothing is sent back to the UI, which
    /// has nothing left to hide. Unscoped by record on purpose: whatever was on screen is what the user
    /// hid, so the identity is free for the next presentation of this alert, including an identical
    /// re-issue arriving while the device is still being told.
    func cardWentDown(_ identity: AlertIdentity) {
        presented.removeValue(forKey: identity)
    }

    /// Reports the occurrence and stops there. Showing the card is the caller's, from the record as it
    /// stands now: the entry captured at scheduling time has no `firedDate` yet and would be rejected
    /// as not presentable, and by the time a repeat comes round it may also have been retracted.
    private func timerReachedOccurrence(_ alert: AlertEntry) {
        reportOccurrence(alert.storageIdentifier)
    }

    private func dismiss(_ identity: AlertIdentity) {
        guard presented.removeValue(forKey: identity) != nil else { return }
        appCoordinator.sendAlertDismissalMessage(identity)
    }

    private func cancelTimer(for identity: AlertIdentity) {
        pending.removeValue(forKey: identity)?.task.cancel()
    }

    private func clearTimer(for identity: AlertIdentity, token: UInt64) {
        guard pending[identity]?.token == token else { return }
        pending[identity] = nil
    }

    /// Occurrences follow the alert's own phase - `scheduledDate` plus whole periods - not the moment
    /// the timer happened to be armed. A timer restarted from `now` after a relaunch would run out of
    /// step with the system's repeating trigger, which keeps the phase it was armed with. The cost is
    /// the one Loop accepts for restored repeating triggers: the first occurrence after a restart can
    /// be up to a period away, which the launch replay covers.
    private static func nextOccurrence(after now: Date, scheduledDate: Date, period: TimeInterval?) -> Date {
        guard let period, period > 0, scheduledDate <= now else { return scheduledDate }
        let periodsElapsed = (now.timeIntervalSince(scheduledDate) / period).rounded(.down) + 1
        return scheduledDate.addingTimeInterval(periodsElapsed * period)
    }
}

extension Alert.InterruptionLevel {
    var unNotificationInterruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        case .critical: return .critical
        }
    }
}
