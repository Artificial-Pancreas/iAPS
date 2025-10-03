import UserNotifications

class NotificationManager {
    private static let logger = MedtrumLogger(category: "NotificationManager")

    private enum Identifiers: String {
        case patchExpiredNotification = "com.nightscout.medtrumkit.patch-expired"
        case patchDailyMaxNotification = "com.nightscout.medtrumkit.patch-daily-limit"
        case patchHourlyMaxNotification = "com.nightscout.medtrumkit.patch-hourly-limit"
        case occlusionNotification = "com.nightscout.medtrumkit.patch-occlussion"
        case patchFaultNotification = "com.nightscout.medtrumkit.patch-fault"
        case reservoirEmptyNotification = "com.nightscout.medtrumkit.patch-empty"
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
    
    public static func clearPendingNotifications() {
        let center = UNUserNotificationCenter.current()
        
        // Can be extended with more scheduled notifications
        for identifier in [Identifiers.patchExpiredNotification] {
            center.removeDeliveredNotifications(withIdentifiers: [identifier.rawValue])
            center.removePendingNotificationRequests(withIdentifiers: [identifier.rawValue])
        }
    }

    public static func patchDailyMaxNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Insulin has been suspended!", comment: "Title insulin suspended notification")
            content.body = LocalizedString("Your patch has reached its daily maximum!", comment: "Body daily max notification")

            addRequest(identifier: .patchDailyMaxNotification, content: content, triggerAfter: nil, deleteOld: true)
        }
    }

    public static func patchHourlyMaxNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Insulin has been suspended!", comment: "Title insulin suspended notification")
            content.body = LocalizedString("Your patch has reached its hourly maximum!", comment: "Body hourly max notification")

            addRequest(identifier: .patchHourlyMaxNotification, content: content, triggerAfter: nil, deleteOld: true)
        }
    }

    public static func occlusionNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Replace your patch now!", comment: "Title replace patch notification")
            content.body = LocalizedString("Your patch has detected an occlussion!", comment: "Body occlussion notification")

            addRequest(identifier: .occlusionNotification, content: content, triggerAfter: nil, deleteOld: true)
        }
    }

    public static func patchFaultNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Replace your patch now!", comment: "Title replace patch notification")
            content.body = LocalizedString("Your patch is in Fault state!", comment: "Body fault notification")

            addRequest(identifier: .patchFaultNotification, content: content, triggerAfter: nil, deleteOld: true)
        }
    }

    public static func reservoirEmptyNotification() {
        ensureCanSendNotification {
            let content = UNMutableNotificationContent()
            content.title = LocalizedString("Replace your patch now!", comment: "Title replace patch notification")
            content.body = LocalizedString("Your patch is out of insulin!", comment: "Body reservoir empty notification")

            addRequest(identifier: .reservoirEmptyNotification, content: content, triggerAfter: nil, deleteOld: true)
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
