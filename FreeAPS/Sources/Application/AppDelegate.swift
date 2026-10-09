import SwiftUI
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // iOS delivers a notification response that launched the app only to a delegate that is already
        // set when launch finishes, so it must be installed synchronously here.
        UNUserNotificationCenter.current().delegate = FreeAPSApp.resolver.resolve(UserNotificationCenterDelegate.self)!
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_: UIApplication) {
        debug(.default, "Protected data did become available")
    }

    func applicationProtectedDataWillBecomeUnavailable(_: UIApplication) {
        debug(.default, "Protected data will become unavailable")
    }
}
