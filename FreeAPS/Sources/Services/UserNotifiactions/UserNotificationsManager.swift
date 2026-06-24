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
        case pumpNotification = "FreeAPS.pumpNotification"
    }

    private let settingsManager: SettingsManager
    private let glucoseStorage: GlucoseStorage
    private let apsManager: APSManager
    private let deviceDataManager: DeviceDataManager
    private let router: Router
    private let appCoordinator: AppCoordinator

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
        appCoordinator: AppCoordinator
    ) {
        self.settingsManager = settingsManager
        self.glucoseStorage = glucoseStorage
        self.apsManager = apsManager
        self.deviceDataManager = deviceDataManager
        self.router = router
        self.appCoordinator = appCoordinator

        self.userNotificationCenterDelegate = UserNotificationCenterDelegate()
    }

    // this is called at the start of the app
    func start() async {
        self.settings = await settingsManager.settings

        userNotificationCenterDelegate.manager = self
        center.delegate = userNotificationCenterDelegate

        observe(appCoordinator.settings) { me, settings in
            await me.settingsUpdated(settings)
        }
        observe(appCoordinator.glucoseHistory.dropFirst()) { me, _ in
            await me.sendGlucoseNotification()
        }
        observe(appCoordinator.loopCompleted) { me, loopOutcome in
            await me.loopCompleted(loopOutcome)
        }
        observe(appCoordinator.bolusFailures) { me, _ in
            await me.notifyBolusFailure()
        }
        observe(appCoordinator.pumpNotifications) { me, alert in
            await me.pumpNotificationTriggered(alert)
        }
        observe(appCoordinator.pumpNotificationsRemove) { me, _ in
            await me.pumpNotificationsRemoved()
        }

        observe(appCoordinator.lastLoopDate) { me, date in
            await me.scheduleMissingLoopNotifiactions(date)
        }

        await requestNotificationPermissionsIfNeeded()
        await sendGlucoseNotification()
    }

    private func settingsUpdated(_ settings: FreeAPSSettings) {
        self.settings = settings
    }

    private func loopCompleted(_ loopOutcome: LoopOutcome) async {
        guard let carndRequired = loopOutcome.suggestion?.carbsReq else { return }
        await notifyCarbsRequired(Int(carndRequired))
    }

    private func pumpNotificationTriggered(_ alert: AlertEntry) async {
        if await ensureCanSendNotification() {
            let content = UNMutableNotificationContent()
            content.title = alert.contentTitle ?? "Unknown"
            content.body = alert.contentBody ?? "Unknown"
            content.sound = .default
            await self.addRequest(
                identifier: .pumpNotification,
                content: content,
                deleteOld: true,
                trigger: nil
            )
        }
    }

    private func pumpNotificationsRemoved() async {
        self.center.removeDeliveredNotifications(withIdentifiers: [Identifier.pumpNotification.rawValue])
        self.center.removePendingNotificationRequests(withIdentifiers: [Identifier.pumpNotification.rawValue])
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
            firstContent.title = title
            firstContent.body = String(format: body, firstInterval)
            if sound { firstContent.sound = .default }

            let secondContent = UNMutableNotificationContent()
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

        let glucose = Array(appCoordinator.glucoseHistory.value.reversed())
        guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { return }

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

            let delta = glucose.count >= 2 ? glucoseValue - (glucose[glucose.count - 2].glucose ?? 0) : nil
            let body = self.glucoseText(glucoseValue: glucoseValue, delta: delta, direction: lastGlucose.direction) + self
                .infoBody()

            if self.snoozeUntilDate > Date() {
                titles.append(NSLocalizedString("(Snoozed)", comment: "(Snoozed)"))
            } else if alert {
                let content = UNMutableNotificationContent()
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

final class UserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var manager: BaseUserNotificationsManager?

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let actionRaw = response.notification.request.content.userInfo[NotificationAction.key] as? String,
              let action = NotificationAction(rawValue: actionRaw),
              let manager
        else {
            return
        }
        Task { await manager.handleNotificationAction(action) }
    }
}
