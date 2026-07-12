import UIKit

enum ProtectedData {
    static var isAvailable: Bool {
        get async {
            await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        }
    }

    static let didBecomeAvailable = UIApplication.protectedDataDidBecomeAvailableNotification
}
