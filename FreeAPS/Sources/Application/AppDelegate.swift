import SwiftUI
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func applicationProtectedDataDidBecomeAvailable(_: UIApplication) {
        debug(.default, "Protected data did become available")
    }

    func applicationProtectedDataWillBecomeUnavailable(_: UIApplication) {
        debug(.default, "Protected data will become unavailable")
    }
}
