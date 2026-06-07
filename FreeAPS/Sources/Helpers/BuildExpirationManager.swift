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
        if hoursRemaining < 24 {
            return NSLocalizedString(
                "Build Expires Soon!",
                comment: "Build expiration alert title when less than a day remains"
            )
        }
        let format = daysRemaining == 1
            ? NSLocalizedString("Build Expiring in %d Day", comment: "Build expiration alert title, singular day")
            : NSLocalizedString("Build Expiring in %d Days", comment: "Build expiration alert title, plural days")
        return String(format: format, daysRemaining)
    }

    var alertMessage: String {
        if hoursRemaining < 24 {
            let h = hoursRemaining
            let format = h == 1
                ? NSLocalizedString(
                    "Your iAPS build expires in %d hour. After expiration the app will not launch until you rebuild.",
                    comment: "Build expiration alert message under a day, singular hour"
                )
                : NSLocalizedString(
                    "Your iAPS build expires in %d hours. After expiration the app will not launch until you rebuild.",
                    comment: "Build expiration alert message under a day, plural hours"
                )
            return String(format: format, h)
        }
        let dateStr = expirationDate.formatted(date: .abbreviated, time: .omitted)
        let format = daysRemaining == 1
            ? NSLocalizedString(
                "Your iAPS build expires on %1$@ (%2$d day remaining). TestFlight builds must be renewed every 90 days.",
                comment: "Build expiration alert message, singular day; %1$@ is the date, %2$d the days remaining"
            )
            : NSLocalizedString(
                "Your iAPS build expires on %1$@ (%2$d days remaining). TestFlight builds must be renewed every 90 days.",
                comment: "Build expiration alert message, plural days; %1$@ is the date, %2$d the days remaining"
            )
        return String(format: format, dateStr, daysRemaining)
    }
}
