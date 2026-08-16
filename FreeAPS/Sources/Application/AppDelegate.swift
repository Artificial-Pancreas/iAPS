import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    /** create the object graph from here rather than from a SwiftUI view */
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLauncher.shared.startIfNeeded()
        return true
    }

    func applicationProtectedDataDidBecomeAvailable(_: UIApplication) {
        debug(.default, "Protected data did become available")
        AppLauncher.shared.startIfNeeded()
    }

    func applicationProtectedDataWillBecomeUnavailable(_: UIApplication) {
        debug(.default, "Protected data will become unavailable")
    }
}
