import Foundation

struct TempTarget: JSON, Identifiable, Equatable, Hashable {
    var id = UUID().uuidString
    let name: String?
    var createdAt: Date
    let targetTop: Decimal?
    let targetBottom: Decimal?
    let duration: Decimal
    let enteredBy: String?
    let reason: String?

    static let manual = "iAPS"
    static let custom = "Temp target"
    static let cancel = "Cancel"

    var displayName: String {
        name ?? reason ?? TempTarget.custom
    }

    /// Name plus the time it ends ("Activity · 14:00"), so the remaining duration is visible at a glance.
    /// Uses the weekday when it ends on another day, or "14:00" would read as today.
    var displayNameWithEndTime: String {
        let sameDay = Calendar.current.isDateInToday(endDate)
        let formatter = sameDay ? TempTarget.timeFormatter : TempTarget.weekdayTimeFormatter
        return displayName + " · " + formatter.string(from: endDate)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    /// Weekday + time ("Tue 14:00" in the locale's form).
    private static let weekdayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return formatter
    }()

    static func == (lhs: TempTarget, rhs: TempTarget) -> Bool {
        lhs.createdAt == rhs.createdAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(createdAt)
    }

    static func cancel(at date: Date) -> TempTarget {
        TempTarget(
            name: TempTarget.cancel,
            createdAt: date,
            targetTop: 0,
            targetBottom: 0,
            duration: 0,
            enteredBy: TempTarget.manual,
            reason: TempTarget.cancel
        )
    }

    /// The "Cancel" entry offered next to the stored presets (Shortcuts). It is not a stored preset, so it
    /// needs a fixed id: Shortcuts persists the chosen entity's id and resolves it again on every run, and
    /// a fresh UUID per call never resolved. Entries stored by `cancel(at:)` keep their own unique ids.
    static let cancelPresetID = "00000000-0000-0000-0000-000000000000"

    static var cancelPreset: TempTarget {
        var preset = cancel(at: Date())
        preset.id = cancelPresetID
        return preset
    }
}

extension TempTarget {
    /// `duration` is in minutes; fractional minutes count (the Watch bridge always kept them).
    var endDate: Date {
        createdAt.addingTimeInterval(.minutes(duration))
    }

    /// a cancel record (duration == 0) is never active
    func isActive(at date: Date) -> Bool {
        duration != 0 && createdAt <= date && date < endDate
    }
}

extension TempTarget {
    /// `==` matches entries by `createdAt` only, as storage does. This compares every field, for views that
    /// show them: a temp target edited in Nightscout keeps its `created_at` and changes its duration.
    func isIdentical(to other: TempTarget) -> Bool {
        id == other.id && name == other.name && createdAt == other.createdAt
            && targetTop == other.targetTop && targetBottom == other.targetBottom && duration == other.duration
            && enteredBy == other.enteredBy && reason == other.reason
    }

    static func identical(_ lhs: TempTarget?, _ rhs: TempTarget?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (lhs?, rhs?): lhs.isIdentical(to: rhs)
        default: false
        }
    }

    static func identical(_ lhs: [TempTarget], _ rhs: [TempTarget]) -> Bool {
        lhs.elementsEqual(rhs) { $0.isIdentical(to: $1) }
    }
}

extension TempTarget {
    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name
        case createdAt = "created_at"
        case targetTop
        case targetBottom
        case duration
        case enteredBy
        case reason
    }
}
