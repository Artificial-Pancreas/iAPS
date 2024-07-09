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
