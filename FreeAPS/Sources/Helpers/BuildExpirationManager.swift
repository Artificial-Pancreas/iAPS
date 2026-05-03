import Foundation

/// Tracks the 90-day TestFlight build lifetime and throttles expiration alerts.
///
/// Alert cadence (matching Loop's behaviour):
///   ≤ 20 days remaining  → show at most once every 2 days
///   <  24 hours remaining → show at most once per hour
final class BuildExpirationManager {
    static let shared = BuildExpirationManager()

    private let defaults = UserDefaults.standard
    private static let lastAlertKey = "iaps.buildExpirationLastAlertDate"
    private static let lifespanDays = 90
    private static let warningDays = 20

    // MARK: - Computed properties

    var expirationDate: Date {
        Calendar.current.date(byAdding: .day, value: Self.lifespanDays, to: Bundle.main.buildDate)
            ?? .distantFuture
    }

    var daysRemaining: Int {
        Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
    }

    var hoursRemaining: Int {
        max(0, Calendar.current.dateComponents([.hour], from: Date(), to: expirationDate).hour ?? 0)
    }

    // MARK: - Alert gating

    var shouldShowAlert: Bool {
        let days = daysRemaining
        guard days >= 0, days <= Self.warningDays else { return false }
        let minInterval: TimeInterval = hoursRemaining < 24 ? 3600 : 2 * 86400
        let last = defaults.object(forKey: Self.lastAlertKey) as? Date ?? .distantPast
        return Date().timeIntervalSince(last) >= minInterval
    }

    func markAlertShown() {
        defaults.set(Date(), forKey: Self.lastAlertKey)
    }

    // MARK: - Alert content

    var alertTitle: String {
        hoursRemaining < 24 ? "Build Expires Soon!" : "Build Expiring in \(daysRemaining) Day\(daysRemaining == 1 ? "" : "s")"
    }

    var alertMessage: String {
        let dateStr = expirationDate.formatted(date: .abbreviated, time: .omitted)
        if hoursRemaining < 24 {
            let h = hoursRemaining
            return "Your iAPS build expires in \(h) hour\(h == 1 ? "" : "s"). " +
                "After expiration the app will not launch until you rebuild."
        }
        return "Your iAPS build expires on \(dateStr) (\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining). " +
            "TestFlight builds must be renewed every 90 days."
    }
}
