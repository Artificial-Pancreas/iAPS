import AudioToolbox
import Foundation
import LoopKit
import SwiftUI
import Swinject
import UIKit
@preconcurrency import UserNotifications

protocol UserNotificationsManager: Sendable {
    func stopSound() async
}

enum GlucoseSourceKey: String {
    case transmitterBattery
    case nightscoutPing
    case description
}

enum NotificationAction: String {
    static let key = "action"

    case snooze
}

actor BaseUserNotificationsManager: UserNotificationsManager, Injectable, LifetimeOwner, AppService {
    private enum Identifier: String {
        case glucocoseNotification = "FreeAPS.glucoseNotification"
        case carbsRequiredNotification = "FreeAPS.carbsRequiredNotification"
        case noLoopFirstNotification = "FreeAPS.noLoopFirstNotification"
        case noLoopSecondNotification = "FreeAPS.noLoopSecondNotification"
        case bolusFailedNotification = "FreeAPS.bolusFailedNotification"
    }

    private let settingsManager: SettingsManager
    private let glucoseStorage: GlucoseStorage
    private let apsManager: APSManager
    private let deviceDataManager: DeviceDataManager
    private let router: Router
    private let appCoordinator: AppCoordinator
    private let deviceAlertManager: DeviceAlertManager

    @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast

    private var settings: FreeAPSSettings!

    private let center = UNUserNotificationCenter.current()
    private let userNotificationCenterDelegate: UserNotificationCenterDelegate
    let lifetime = Lifetime()

    init(
        settingsManager: SettingsManager,
        glucoseStorage: GlucoseStorage,
        apsManager: APSManager,
        deviceDataManager: DeviceDataManager,
        router: Router,
        appCoordinator: AppCoordinator,
        deviceAlertManager: DeviceAlertManager,
        userNotificationCenterDelegate: UserNotificationCenterDelegate
    ) {
        self.settingsManager = settingsManager
        self.glucoseStorage = glucoseStorage
        self.apsManager = apsManager
        self.deviceDataManager = deviceDataManager
        self.router = router
        self.appCoordinator = appCoordinator
        self.deviceAlertManager = deviceAlertManager
        self.userNotificationCenterDelegate = userNotificationCenterDelegate
    }

    // this is called at the start of the app
    func start() async {
        self.settings = await settingsManager.settings

        // The delegate is installed on the center in AppDelegate at launch (so a response that launched
        // the app is not lost); only the back-reference to this manager is wired here. Responses that
        // arrived before this point were buffered by the delegate and are flushed by `attach`.
        userNotificationCenterDelegate.attach(manager: self)
        registerDeviceAlertCategory()

        observe(appCoordinator.settings) { me, settings in
            await me.settingsUpdated(settings)
        }
        observe(appCoordinator.glucoseRaw.dropFirst()) { me, _ in
            await me.sendGlucoseNotification()
        }
        observe(appCoordinator.loopCompleted) { me, loopOutcome in
            await me.loopCompleted(loopOutcome)
        }
        observe(appCoordinator.bolusFailures) { me, _ in
            await me.notifyBolusFailure()
        }

        observe(appCoordinator.lastLoopDate) { me, date in
            await me.scheduleMissingLoopNotifiactions(date)
        }

        await requestNotificationPermissionsIfNeeded()
        await sendGlucoseNotification()
    }

    private func registerDeviceAlertCategory() {
        let acknowledgeAction = UNNotificationAction(
            identifier: DeviceAlertNotification.acknowledgeActionIdentifier,
            title: NSLocalizedString("OK", comment: "Acknowledge a device alert"),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: DeviceAlertNotification.categoryIdentifier,
            actions: [acknowledgeAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        // The only category the app registers, so replace the set outright rather than read and merge.
        center.setNotificationCategories([category])
    }

    /// Both only hand the record to `DeviceAlertManager`, which queues it, so neither touches actor
    /// state and neither needs awaiting. `nonisolated` on purpose: it lets the notification delegate
    /// stay synchronous and call its completion handler on the main thread it was invoked on, which
    /// UIKit requires.
    fileprivate nonisolated func deviceAlertWillPresent(recordIdentifier: String) {
        deviceAlertManager.notificationWillPresent(recordIdentifier: recordIdentifier)
    }

    fileprivate nonisolated func deviceAlertWasOpened(recordIdentifier: String) {
        deviceAlertManager.notificationWasOpened(recordIdentifier: recordIdentifier)
    }

    fileprivate func acknowledgeDeviceAlert(recordIdentifier: String, identity: AlertIdentity?) async {
        guard let identity else {
            // No identity to route back to a device; all that is left is to record the delivery.
            deviceAlertManager.notificationWillPresent(recordIdentifier: recordIdentifier)
            return
        }
        await deviceDataManager.acknowledgeDeviceAlert(identity, recordIdentifier: recordIdentifier)
    }

    private func settingsUpdated(_ settings: FreeAPSSettings) {
        self.settings = settings
    }

    private func loopCompleted(_ loopOutcome: LoopOutcome) async {
        guard let carndRequired = loopOutcome.suggestion?.carbsReq else { return }
        await notifyCarbsRequired(Int(carndRequired))
    }

    private func addAppBadge(glucose: Int?) async {
        let badge: Int
        if let glucose = glucose, settings.glucoseBadge {
            if settings.units == .mmolL {
                badge = Int(round(Double((glucose * 10).asMmolL)))
            } else {
                badge = glucose
            }
        } else {
            badge = 0
        }

        do {
            try await center.setBadgeCount(badge)
        } catch {
            debug(.service, "Failed to set badge count: \(error.localizedDescription)")
        }
    }

    private func notifyCarbsRequired(_ carbs: Int) async {
        guard settings.carbsRequiredAlert,
              Decimal(carbs) >= settings.carbsRequiredThreshold
        else { return
        }
        let sound = settings.carbSound

        if await ensureCanSendNotification() {
            var titles: [String] = []

            let content = UNMutableNotificationContent()

            if self.snoozeUntilDate > Date() {
                titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
            } else {
                if sound == "Default" {
                    if self.settings.useAlarmSound {
                        content.sound = .default
                    }
                } else if sound != "Silent" {
                    self.playSoundIfNeeded(sound: sound)
                }
            }

            titles.append(String(format: NSLocalizedString("Carbs required: %d g", comment: "Carbs required"), carbs))

            content.interruptionLevel = .timeSensitive
            content.title = titles.joined(separator: " ")
            content.body = String(
                format: NSLocalizedString(
                    "To prevent LOW required %d g of carbs",
                    comment: "To prevent LOW required %d g of carbs"
                ),
                carbs
            )

            await self.addRequest(identifier: .carbsRequiredNotification, content: content, deleteOld: true)
        }
    }

    private func scheduleMissingLoopNotifiactions(_: Date?) async {
        let sound = settings.missingLoops
        if await ensureCanSendNotification() {
            let title = NSLocalizedString("iAPS not active", comment: "iAPS not active")
            let body = NSLocalizedString("Last loop was more than %d min ago", comment: "Last loop was more than %d min ago")

            let firstInterval = 20 // min
            let secondInterval = 40 // min

            let firstContent = UNMutableNotificationContent()
            firstContent.interruptionLevel = .timeSensitive
            firstContent.title = title
            firstContent.body = String(format: body, firstInterval)
            if sound { firstContent.sound = .default }

            let secondContent = UNMutableNotificationContent()
            secondContent.interruptionLevel = .timeSensitive
            secondContent.title = title
            secondContent.body = String(format: body, secondInterval)
            if sound { secondContent.sound = .default }

            let firstTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * TimeInterval(firstInterval), repeats: false)
            let secondTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 60 * TimeInterval(secondInterval), repeats: false)

            await self.addRequest(
                identifier: .noLoopFirstNotification,
                content: firstContent,
                deleteOld: true,
                trigger: firstTrigger
            )
            await self.addRequest(
                identifier: .noLoopSecondNotification,
                content: secondContent,
                deleteOld: true,
                trigger: secondTrigger
            )
        }
    }

    private func notifyBolusFailure() async {
        let sound = settings.bolusFailure
        if await ensureCanSendNotification() {
            let title = NSLocalizedString("Bolus failed", comment: "Bolus failed")
            let body = NSLocalizedString(
                "Bolus failed or inaccurate. Check pump history before repeating.",
                comment: "Bolus failed or inaccurate. Check pump history before repeating."
            )

            let content = UNMutableNotificationContent()
            content.interruptionLevel = .timeSensitive
            content.title = title
            content.body = body
            if sound == "Default" {
                if self.settings.useAlarmSound {
                    content.sound = .default
                }
            } else if sound != "Silent" {
                self.playSoundIfNeeded(sound: sound)
            }

            await self.addRequest(
                identifier: .bolusFailedNotification,
                content: content,
                deleteOld: true
            )
        }
    }

    private func sendGlucoseNotification() async {
        await addAppBadge(glucose: nil)

        let glucose = Array(appCoordinator.glucoseRaw.value.reversed())
        guard let lastGlucose = glucose.last else { return }
        let glucoseValue = lastGlucose.glucose

        await addAppBadge(glucose: lastGlucose.glucose)

        let alarm = appCoordinator.glucoseAlarm.value
        guard alarm != nil || settings.glucoseNotificationsAlways else {
            return
        }

        if await ensureCanSendNotification() {
            var titles: [String] = []
            var sound: String = "New/Anticipalte.caf"
            var alert = true

            switch alarm {
            case .none:
                titles.append(NSLocalizedString("Glucose", comment: "Glucose"))
                sound = "Silent"
            case .low:
                titles.append(NSLocalizedString("LOWALERT!", comment: "LOWALERT!"))
                sound = self.settings.hypoSound
                alert = self.settings.lowAlert
            case .high:
                titles.append(NSLocalizedString("HIGHALERT!", comment: "HIGHALERT!"))
                sound = self.settings.hyperSound
                alert = self.settings.highAlert
            case .ascending:
                titles.append(NSLocalizedString("RAPIDLY ASCENDING GLUCOSE!", comment: "RAPIDLY ASCENDING GLUCOSE!"))
                sound = self.settings.ascending
                alert = self.settings.ascendingAlert
            case .descending:
                titles.append(NSLocalizedString("RAPIDLY DESCENDING GLUCOSE!", comment: "RAPIDLY DESCENDING GLUCOSE!"))
                sound = self.settings.descending
                alert = self.settings.descendingAlert
            }

            let delta = glucose.count >= 2 ? glucoseValue - glucose[glucose.count - 2].glucose : nil
            let body = self.glucoseText(glucoseValue: glucoseValue, delta: delta, direction: lastGlucose.direction) + self
                .infoBody()

            if self.snoozeUntilDate > Date() {
                titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
            } else if alert {
                let content = UNMutableNotificationContent()
                // Only an actual alarm earns the right to break through Focus. The `.none` case is
                // the routine reading posted by `glucoseNotificationsAlways`, which arrives every
                // cycle and stays an ordinary notification.
                content.interruptionLevel = alarm == nil ? .active : .timeSensitive
                content.title = titles.joined(separator: " ")
                content.body = body

                if sound != "Silent", self.settings.useAlarmSound {
                    content.userInfo[NotificationAction.key] = NotificationAction.snooze.rawValue
                    if sound == "Default" {
                        content.sound = .default
                    } else {
                        self.playSoundIfNeeded(sound: sound)
                    }
                }

                await self.addRequest(identifier: .glucocoseNotification, content: content, deleteOld: true)
            }
        }
    }

    private func glucoseText(glucoseValue: Int, delta: Int?, direction: BloodGlucose.Direction?) -> String {
        let units = settings.units
        let glucoseText = glucoseFormatter
            .string(from: Double(
                units == .mmolL ? glucoseValue
                    .asMmolL : Decimal(glucoseValue)
            ) as NSNumber)! + " " + NSLocalizedString(units.rawValue, comment: "units")
        let directionText = direction?.symbol ?? "↔︎"
        let deltaText = delta
            .map {
                Self.deltaFormatter
                    .string(from: Double(
                        units == .mmolL ? $0
                            .asMmolL : Decimal($0)
                    ) as NSNumber)!
            } ?? "--"

        return glucoseText + " " + directionText + " " + deltaText
    }

    private func infoBody() -> String {
        guard settings.addSourceInfoToGlucoseNotifications,
              let info = deviceDataManager.cgmInfo()
        else {
            return ""
        }

        var body = ""

        // Description
        if let description = info.description {
            body.append("\n" + description)
        }

        // Transmitter battery
        if let transmitterBattery = info.transmitterBattery {
            body.append(
                "\n"
                    + String(
                        format: NSLocalizedString("Transmitter: %@%%", comment: "Transmitter: %@%%"),
                        "\(transmitterBattery)"
                    )
            )
        }

        return body
    }

    private func requestNotificationPermissionsIfNeeded() async {
        let notificationSettings = await center.notificationSettings()
        debug(
            .service,
            "UNUserNotificationCenter.authorizationStatus: \(String(describing: notificationSettings.authorizationStatus))"
        )
        if ![.authorized, .provisional].contains(notificationSettings.authorizationStatus) {
            await self.requestNotificationPermissions()
        }
    }

    private func requestNotificationPermissions() async {
        debug(.service, "requestNotificationPermissions")
        do {
            let granted = try await center.requestAuthorization(options: [.badge, .sound, .alert])
            if granted {
                debug(.service, "requestNotificationPermissions was granted")
            } else {
                warning(.service, "requestNotificationPermissions failed")
            }
        } catch {
            warning(.service, "requestNotificationPermissions failed", error: error)
        }
    }

    private func ensureCanSendNotification() async -> Bool {
        let notificationSettings = await center.notificationSettings()
        guard notificationSettings.authorizationStatus == .authorized || notificationSettings.authorizationStatus == .provisional
        else {
            warning(.service, "ensureCanSendNotification failed, authorization denied")
            return false
        }
        debug(.service, "Sending notification was allowed")

        return true
    }

    private func addRequest(
        identifier: Identifier,
        content: UNMutableNotificationContent,
        deleteOld: Bool = false,
        trigger: UNNotificationTrigger? = nil
    ) async {
        if deleteOld {
            self.center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            self.center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: trigger)

        do {
            try await self.center.add(request)
            debug(.service, "Sending \(identifier) notification")
        } catch {
            warning(.service, "Unable to addNotificationRequest", error: error)
        }
    }

    private func playSoundIfNeeded(sound: String) {
        guard settings.useAlarmSound, snoozeUntilDate < Date() else { return }
        guard sound != "Silent" else { return }

        playSound(sound: sound)
    }

    private var soundTask: Task<Void, Never>?

    private func playSound(sound: String, times: Int = 1) {
        soundTask?.cancel()
        soundTask = Task {
            let path = "/System/Library/Audio/UISounds/" + sound
            guard let url = URL(string: path) else { return }

            var id: UInt32 = 0
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            defer { AudioServicesDisposeSystemSoundID(id) }

            for _ in 0 ..< times {
                guard !Task.isCancelled else { return }
                await withCheckedContinuation { continuation in
                    AudioServicesPlaySystemSoundWithCompletion(id) {
                        continuation.resume()
                    }
                }
            }
        }
    }

    func stopSound() {
        soundTask?.cancel()
        soundTask = nil
    }

    private var glucoseFormatter: NumberFormatter {
        switch settings.units {
        case .mmolL: return Self.glucoseFormatterMmol
        case .mgdL: return Self.glucoseFormatterMgdl
        }
    }

    private static let glucoseFormatterMmol = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let glucoseFormatterMgdl = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.roundingMode = .halfUp
        return formatter
    }()

    private static let deltaFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }()

    fileprivate func handleNotificationAction(_ action: NotificationAction) async {
        switch action {
        case .snooze:
            await MainActor.run {
                router.mainModalScreen.send(.snooze)
            }
        }
    }
}

/// UIKit hands the delegate a plain, non-Sendable closure, and `UNUserNotificationCenterDelegate` is
/// not main-actor annotated, so carrying one across an `await` needs a box. Safe as unchecked: the
/// handler is called exactly once and nothing else ever reads it. `callAsFunction` is `@MainActor`
/// because UIKit asserts if these are called anywhere else - that way it cannot be called wrongly.
private final class NotificationCompletion: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @MainActor func callAsFunction() {
        handler()
    }
}

/// Shared between `AppDelegate`, which installs it at launch, and `BaseUserNotificationsManager`, which
/// wires itself in once started (service startup is long and async, so responses - including the one
/// that launched the app - can arrive first). Only device-alert responses are buffered and replayed by
/// `attach(manager:)`: those carry an acknowledgement that must reach the device. Every other response
/// (glucose/loop notifications, snooze actions, ...) arriving before the manager is completed at once
/// and dropped, as it was before the buffer existed.
///
/// `@unchecked Sendable` invariant: every piece of mutable state (`_manager`, `pendingResponses`) is
/// touched only inside `lock`, and nothing is handed out of the lock except values the caller then owns.
/// The lock is never held across a call into the manager or a completion handler.
final class UserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let lock = NSLock(label: "UserNotificationCenterDelegate")
    private weak var _manager: BaseUserNotificationsManager?
    /// Device-alert responses received before the manager was wired, oldest first. Their completion
    /// handlers are deliberately *not* called while they sit here - iOS waits for the answer until the
    /// response has actually been handled. If the manager is never wired (startup failed) they are never
    /// called and iOS eventually logs a warning; that is accepted rather than papered over with a timer,
    /// because calling the handler early would silently drop a device-alert acknowledgement. Only
    /// device-alert responses are held to that standard; the rest are completed immediately.
    private var pendingResponses: [(response: UNNotificationResponse, completion: NotificationCompletion)] = []

    private var manager: BaseUserNotificationsManager? {
        lock.perform { _manager }
    }

    /// Stores the back-reference and replays anything that arrived before it, in order.
    func attach(manager: BaseUserNotificationsManager) {
        let pending: [(response: UNNotificationResponse, completion: NotificationCompletion)] = lock.perform {
            _manager = manager
            let pending = pendingResponses
            pendingResponses = []
            return pending
        }
        for entry in pending {
            handle(response: entry.response, completion: entry.completion, manager: manager)
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if let recordIdentifier = DeviceAlertNotification.recordIdentifier(from: notification.request.content) {
            // iOS needs the presentation options right now, so this cannot be buffered. Without a manager
            // the delivery simply is not recorded; the notification is still presented as usual.
            manager?.deviceAlertWillPresent(recordIdentifier: recordIdentifier)
            // `.list` is what keeps a notification delivered in the foreground in Notification Centre
            // and on the lock screen; without it iOS shows the banner once and discards it, leaving
            // nothing to act on later. An alert with no foreground content is not bannered over the app
            // (the in-app card is the foreground surface) but is still listed, as Loop does.
            completionHandler(
                DeviceAlertNotification.hasForegroundContent(notification.request.content) ?
                    [.banner, .badge, .sound, .list] : [.badge, .sound, .list]
            )
            return
        }
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let completion = NotificationCompletion(completionHandler)
        let isDeviceAlert = DeviceAlertNotification.recordIdentifier(from: response.notification.request.content) != nil
        // Checked and buffered under one lock so a response cannot slip between the check and `attach`.
        // Only device-alert responses are worth waiting for; anything else is answered right away.
        let manager: BaseUserNotificationsManager? = lock.perform {
            if let _manager { return _manager }
            if isDeviceAlert {
                pendingResponses.append((response: response, completion: completion))
            }
            return nil
        }
        guard let manager else {
            if !isDeviceAlert { Task { await completion() } }
            return
        }
        handle(response: response, completion: completion, manager: manager)
    }

    /// The one place a response is acted on, used both live and when replaying the buffer. Callable from
    /// any thread: it never touches UIKit itself, and `NotificationCompletion` hops to the main actor.
    private func handle(
        response: UNNotificationResponse,
        completion: NotificationCompletion,
        manager: BaseUserNotificationsManager
    ) {
        if let recordIdentifier = DeviceAlertNotification.recordIdentifier(from: response.notification.request.content) {
            if response.actionIdentifier == DeviceAlertNotification.acknowledgeActionIdentifier ||
                response.actionIdentifier == UNNotificationDismissActionIdentifier
            {
                let identity = DeviceAlertNotification.alertIdentity(from: response.notification.request.content)
                // device acknowledgement can take a while
                Task {
                    await withBackgroundTask("acknowledge device alert") {
                        await manager.acknowledgeDeviceAlert(
                            recordIdentifier: recordIdentifier,
                            identity: identity
                        )
                    }
                    await completion()
                }
            } else {
                // Opening the notification is an explicit request to see the alert
                manager.deviceAlertWasOpened(recordIdentifier: recordIdentifier)
                Task { await completion() }
            }
            return
        }

        if let actionRaw = response.notification.request.content.userInfo[NotificationAction.key] as? String,
           let action = NotificationAction(rawValue: actionRaw)
        {
            Task { await manager.handleNotificationAction(action) }
        }
        Task { await completion() }
    }
}
