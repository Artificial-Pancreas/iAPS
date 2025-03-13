import Foundation

struct DatabasePumpSettings: JSON {
    var report = "pumpSettings"
    let settings: PumpSettings?
    let enteredBy: String
    let profile: String?
}

struct DatabaseTempTargets: JSON {
    var report = "tempTargets"
    let tempTargets: [TempTarget]
    let enteredBy: String
    let profile: String?
}

struct DatabaseProfileStore: JSON {
    var report = "profiles"
    let units: String
    var enteredBy: String
    let store: [String: ScheduledNightscoutProfile]
    var profile: String
}

struct NightscoutStatistics: JSON {
    var report = "statistics"
    let dailystats: Statistics?
    let justVersion: BareMinimum?
}

struct NightscoutPreferences: JSON {
    var report = "preferences"
    let preferences: Preferences?
    let enteredBy: String
    let profile: String?
}

struct NightscoutSettings: JSON {
    var report = "settings"
    let settings: FreeAPSSettings?
    let enteredBy: String
    let profile: String?
}

struct Loaded {
    var sens = false
    var settings = false
    var preferences = false
    var targets = false
    var carbratios = false
    var basalProfiles = false
}

struct ProfileList: JSON {
    var profiles: String
}

struct MigratedMeals: Codable {
    var carbs: Decimal
    var dish: String
    var fat: Decimal
    var protein: Decimal
}

struct MigratedOverridePresets: Codable {
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

struct MealDatabase: JSON {
    var report = "mealPresets"
    var profile: String
    var presets: [MigratedMeals]
    let enteredBy: String
}

struct OverrideDatabase: JSON {
    var report = "overridePresets"
    var profile: String
    var presets: [MigratedOverridePresets]
    let enteredBy: String
}
