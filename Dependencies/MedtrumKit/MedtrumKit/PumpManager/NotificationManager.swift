import UserNotifications

class NotificationManager {
    private static let logger = MedtrumLogger(category: "NotificationManager")

    private enum Identifiers: String {
        case patchExpiredNotification = "com.nightscout.medtrumkit.patch-expired"
    }

    public static func activatePatchExpiredNotification(after: TimeInterval) {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Your patch will expire soon!", comment: "Title expire reminder notification")
            content.body = String(
                format: LocalizedString("Your patch has %i hours left", comment: "Body expire reminder notification"),
                Int(80 - after.hours)
            )

            addRequest(identifier: .patchExpiredNotification, content: content, triggerAfter: after, deleteOld: true)
        }
    }

    private static func addRequest(
        identifier: Identifiers,
        content: UNMutableNotificationContent,
        triggerAfter: TimeInterval? = nil,
        deleteOld: Bool = false
    ) {
        let center = UNUserNotificationCenter.current()
        var trigger: UNCalendarNotificationTrigger?

        if deleteOld {
            // Required since ios12+ have started to cache/group notifications
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }

        if let triggerAfter = triggerAfter {
            let notifTime = Date.now.addingTimeInterval(triggerAfter)
            let dateComponents = Calendar.current.dateComponents([.day, .hour, .minute], from: notifTime)

            trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        }

        let request = UNNotificationRequest(identifier: identifier.rawValue, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                logger.info("unable to addNotificationRequest: \(error.localizedDescription)")
                return
            }

            logger.info("sending \(identifier.rawValue) notification")
        }
    }

    private static func ensureCanSendNotification(_ completion: @escaping () -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                logger.warning("ensureCanSendNotification failed, authorization denied")
                return
            }

            completion()
        }
    }
}
