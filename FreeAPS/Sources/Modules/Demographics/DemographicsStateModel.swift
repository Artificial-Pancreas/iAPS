import Foundation
import SwiftUI

/// Settings › Configuration › Demographics: the sex, the birth date, the weight and the height, stored on the phone (the
/// reference intakes in Statistics › Nutrients use the first two). Settings › Sharing sets whether the daily statistics
/// carry the sex and the age (`DemographicsSharing`); the settings backup carries all four.
enum Demographics {
    enum Config {}
}

protocol DemographicsProvider: Provider {}

extension Demographics {
    final class Provider: BaseProvider, DemographicsProvider {}

    final class StateModel: BaseStateModel<Provider> {
        // The sex, the birth date and their share toggles (set in Settings › Sharing, read for the Sharing row's
        // summary), as one setting: a value cleared turns its toggle off in the same update (`settingSex`,
        // `settingBirthDate`).
        @Setting(\.demographics) var demographics = DemographicsSharing()
        // Weight stored canonically in kg, height in cm (0 = unset); the display units are preferences.
        @Setting(\.weight) var weight: Decimal = 0
        @Setting(\.height) var height: Decimal = 0
        @Setting(\.weightInLb) var weightInLb: Bool = false
        @Setting(\.heightInFtIn) var heightInFtIn: Bool = false
        // Settings › Sharing's Online Backup and Statistics: off, nothing is uploaded (the Sharing row's summary).
        // Read only, and followed while shown.
        @Setting(\.uploadStats) private(set) var uploadStats: Bool = false

        var sex: Sex {
            get { Sex.savedSettings(demographics.sexSetting) }
            set { demographics = demographics.settingSex(newValue.saveSetting()) }
        }

        /// The birth date picked, as its day (`DemographicsSharing.shownBirthDay`), nil when not set
        /// (`BirthDateField`). Stored only when a day is picked or the date cleared.
        var pickedBirthDate: Date? {
            get { demographics.shownBirthDay }
            set {
                demographics = demographics.settingBirthDate(newValue.map(DemographicsSharing.birthDate(day:)) ?? .distantPast)
            }
        }
    }
}

// MARK: - Formatting (also the Sharing screen's)

extension Demographics {
    private static let lbPerKg = 2.2046226218
    /// exact: an inch is 2.54 cm by definition
    private static let cmPerInch = Decimal(254) / 100

    /// "Born 14 March 1985"; nil when not set.
    static func bornText(_ birthDate: Date) -> String? {
        dayText(birthDate, style: .long).map {
            String(format: NSLocalizedString("Born %@", comment: "Sharing: the birth date, \"14 March 1985\""), $0)
        }
    }

    /// "14 Mar 1985"; nil when not set.
    static func bornShortText(_ birthDate: Date) -> String? {
        dayText(birthDate, style: .medium)
    }

    /// whole feet and the inches left, rounded (12 inches carry over to a foot)
    static func feetInches(cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((cm / NSDecimalNumber(decimal: cmPerInch).doubleValue).rounded())
        return (totalInches / 12, totalInches % 12)
    }

    static func cm(feet: Int, inches: Int) -> Decimal {
        Decimal(feet * 12 + inches) * cmPerInch
    }

    /// The height for feet and inches entered: `current` when they are its own (`feetInches`), so filling the fields
    /// from a height in cm and committing them as they are doesn't turn 172 cm into 172.72; 0 (not set) for 0 ft 0 in.
    static func height(feet: Int, inches: Int, keeping current: Decimal) -> Decimal {
        let feet = max(0, feet)
        let inches = max(0, inches)
        let split = feetInches(cm: NSDecimalNumber(decimal: current).doubleValue)
        if current > 0, split.feet == feet, split.inches == inches {
            return current
        }
        return cm(feet: feet, inches: inches)
    }

    static func weightField(kg: Decimal, inLb: Bool) -> Double {
        let kg = NSDecimalNumber(decimal: kg).doubleValue
        return inLb ? kg * lbPerKg : kg
    }

    static func kg(field: Double, inLb: Bool) -> Decimal {
        Decimal(max(0, inLb ? field / lbPerKg : field))
    }

    /// The day (`DemographicsSharing.birthDay`), in `DemographicsSharing.birthCalendar`'s time zone (the day kept,
    /// wherever the phone is).
    private static func dayText(_ birthDate: Date, style: DateFormatter.Style) -> String? {
        guard birthDate != .distantPast else { return nil }
        let formatter = DateFormatter()
        formatter.timeZone = DemographicsSharing.birthCalendar.timeZone
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: DemographicsSharing.birthDay(birthDate))
    }
}
