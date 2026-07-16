import Foundation

struct DatabasePumpSettings: JSON {
    let settings: PumpSettings?
    let profile: String?
    /// Insulin concentration factor: 1.0 = U100 (standard), 2.0 = U200, etc.
    let insulinConcentration: Double?
}

struct DatabaseTempTargets: JSON {
    let tempTargets: [TempTarget]
    let profile: String?
}

struct DatabaseProfileStore: JSON {
    var report = "profiles"
    let units: String
    var enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    var profile: String
}

struct DatabaseStatisticsVersion: JSON, Equatable {
    var created_at: Date
    var Build_Version: String
    var Branch: String
    var id: String?
}

struct DatabasePreferences: JSON {
    let preferences: Preferences?
    let profile: String?
}

struct DatabaseSettings: JSON {
    let settings: FreeAPSSettings?
    let profile: String?
}

struct ProfileList: JSON {
    var profiles: String
}

struct MigratedMeals: Codable, Equatable {
    var carbs: Decimal
    var dish: String
    var fat: Decimal
    var protein: Decimal
}

struct MigratedOverridePresets: Codable, Equatable {
    var advancedSettings: Bool
    var cr: Bool
    var date: Date
    var duration: Decimal
    var emoji: String
    var end: Decimal
    var id: String
    var indefininite: Bool
    var isf: Bool
    var isndAndCr: Bool
    var basal: Bool
    var maxIOB: Decimal
    var name: String
    var overrideMaxIOB: Bool
    var percentage: Double
    var smbAlwaysOff: Bool
    var smbIsOff: Bool
    var smbMinutes: Decimal
    var start: Decimal
    var target: Decimal
    var uamMinutes: Decimal
}

struct DatabaseMeal: JSON, Equatable {
    var profile: String
    var presets: [MigratedMeals]
}

struct DatabaseOverride: JSON, Equatable {
    var profile: String
    var presets: [MigratedOverridePresets]
}
