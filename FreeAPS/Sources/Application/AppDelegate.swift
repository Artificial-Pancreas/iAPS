import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject, UNUserNotificationCenterDelegate {
    var fetchGlucoseManager: FetchGlucoseManager?
    var remoteNotificationsManager: RemoteNotificationsManager? {
        didSet {
            if let token = deviceToken {
                remoteNotificationsManager?.setDeviceToken(token)
            }
        }
    }

    private var deviceToken: String?

    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        if let remoteNotificationsManager = self.remoteNotificationsManager {
            remoteNotificationsManager.setDeviceToken(token)
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        warning(.service, "APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        debug(.apsManager, "remote notification: \(userInfo)")

        let since = userInfo["since"] as? String

//        if let since = since,
//           let date = ISO8601Parsing.parse(since)
//        {
        Task {
            await fetchGlucoseManager?.refreshCGM()
        }
//        } else {
//            warning(.service, "remote notification, invalid date: \(String(describing: since))")
//        }
        completion(.noData)
    }
}
