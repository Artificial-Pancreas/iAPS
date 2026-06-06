import Foundation

extension TimeInterval {
    static func seconds(_ seconds: Double) -> TimeInterval {
        seconds
    }

    static func seconds(_ seconds: Decimal) -> TimeInterval {
        Double(seconds)
    }

    static func seconds(_ seconds: Int) -> TimeInterval {
        Double(seconds)
    }

    static func minutes(_ minutes: Double) -> TimeInterval {
        TimeInterval(minutes: minutes)
    }

    static func minutes(_ minutes: Decimal) -> TimeInterval {
        TimeInterval(minutes: Double(minutes))
    }

    static func minutes(_ minutes: Int) -> TimeInterval {
        TimeInterval(minutes: Double(minutes))
    }

    static func hours(_ hours: Double) -> TimeInterval {
        TimeInterval(hours: hours)
    }

    static func hours(_ hours: Decimal) -> TimeInterval {
        TimeInterval(hours: Double(hours))
    }

    static func hours(_ hours: Int) -> TimeInterval {
        TimeInterval(hours: Double(hours))
    }

    static func days(_ days: Double) -> TimeInterval {
        TimeInterval(days: days)
    }

    static func days(_ days: Decimal) -> TimeInterval {
        TimeInterval(days: Double(days))
    }

    static func days(_ days: Int) -> TimeInterval {
        TimeInterval(days: Double(days))
    }

    init(minutes: Double) {
        self.init(minutes * 60)
    }

    init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    init(days: Double) {
        self.init(hours: days * 24)
    }

    var minutes: Double {
        self / 60.0
    }

    var hours: Double {
        minutes / 60.0
    }
}
