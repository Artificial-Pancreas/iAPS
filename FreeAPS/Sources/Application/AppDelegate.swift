import SwiftUI
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    @Published var notificationAction: NotificationAction? = nil

    func application(_: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let action = response.notification.request.content.userInfo["action"] as? String {
            notificationAction = NotificationAction(rawValue: action)
        }
        completionHandler()
    }
}

enum NotificationAction: String {
    case snoozeAlert = "snooze"
}
