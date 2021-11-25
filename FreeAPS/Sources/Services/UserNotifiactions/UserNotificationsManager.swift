import AudioToolbox
import Foundation
import Swinject
import UIKit
import UserNotifications

protocol UserNotificationsManager {}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    private enum Identifier: String {
        case glucocoseNotification = "FreeAPS.glucoseNotification"
    }

    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!

    private let center = UNUserNotificationCenter.current()

    init(resolver: Resolver) {
        super.init()
        center.delegate = self
        injectServices(resolver)
        broadcaster.register(GlucoseObserver.self, observer: self)

        requestNotificationPermissionsIfNeeded()
        sendGlucoseNotification()
    }

    private func addAppBadge(glucose: Int?) {
        guard let glucose = glucose, settingsManager.settings.glucoseBadge else {
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
            return
        }

        let badge: Int
        if settingsManager.settings.units == .mmolL {
            badge = Int(round(Double((glucose * 10).asMmolL)))
        } else {
            badge = glucose
        }

        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = badge
        }
    }

    private func sendGlucoseNotification() {
        addAppBadge(glucose: nil)

        ensureCanSendNotification {
            let glucose = self.glucoseStorage.recent()
            guard let lastGlucose = glucose.last, let glucoseValue = lastGlucose.glucose else { return }

            let delta: Int?
            if glucose.count >= 2 {
                delta = glucoseValue - (glucose[glucose.count - 2].glucose ?? 0)
            } else {
                delta = nil
            }

            let content = UNMutableNotificationContent()

            var titles: [String] = []

            switch self.glucoseStorage.alarm {
            case .none:
                titles.append(NSLocalizedString("Glucose", comment: "Glucose"))
            case .low:
                titles.append(NSLocalizedString("LOWALERT!", comment: "LOWALERT!"))
                self.playSound()
            case .high:
                titles.append(NSLocalizedString("HIGHALERT!", comment: "HIGHALERT!"))
                self.playSound()
            }

            let units = self.settingsManager.settings.units

            let glucoseText = self.glucoseFormatter
                .string(from: Double(
                    units == .mmolL ? glucoseValue
                        .asMmolL : Decimal(glucoseValue)
                ) as NSNumber)! + " " + NSLocalizedString(units.rawValue, comment: "units")
            let directionText = lastGlucose.direction?.symbol ?? "↔︎"
            let deltaText = delta
                .map {
                    self.deltaFormatter
                        .string(from: Double(
                            units == .mmolL ? $0
                                .asMmolL : Decimal($0)
                        ) as NSNumber)!
                } ?? "--"

            let body = glucoseText + " " + directionText + " " + deltaText
            titles.append(body)

            content.title = titles.joined(separator: " ")
            content.body = body

            self.addAppBadge(glucose: lastGlucose.glucose)

            self.addRequest(identifier: .glucocoseNotification, content: content, deleteOld: true)
        }
    }

    private func requestNotificationPermissionsIfNeeded() {
        center.getNotificationSettings { settings in
            debug(.service, "UNUserNotificationCenter.authorizationStatus: \(String(describing: settings.authorizationStatus))")
            if ![.authorized, .provisional].contains(settings.authorizationStatus) {
                self.requestNotificationPermissions()
            }
        }
    }

    private func requestNotificationPermissions() {
        debug(.service, "requestNotificationPermissions")
        center.requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if granted {
                debug(.service, "requestNotificationPermissions was granted")
            } else {
                warning(.service, "requestNotificationPermissions failed", error: error)
            }
        }
    }

    private func ensureCanSendNotification(_ completion: @escaping () -> Void) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                warning(.service, "ensureCanSendNotification failed, authorization denied")
                return
            }

            debug(.service, "Sending notification was allowed")

            completion()
        }
    }

    private func addRequest(identifier: Identifier, content: UNMutableNotificationContent, deleteOld: Bool = false) {
        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: nil)

        if deleteOld {
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        center.add(request) { error in
            if let error = error {
                warning(.service, "Unable to addNotificationRequest", error: error)
                return
            }

            debug(.service, "Sending \(identifier) notification")
        }
    }

    private func playSound(times: Int = 3) {
        guard times > 0 else {
            return
        }

        AudioServicesPlaySystemSoundWithCompletion(1336) {
            self.playSound(times: times - 1)
        }
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter
    }
}

extension BaseUserNotificationsManager: GlucoseObserver {
    func glucoseDidUpdate(_: [BloodGlucose]) {
        sendGlucoseNotification()
    }
}

extension BaseUserNotificationsManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
