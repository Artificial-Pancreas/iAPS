import Foundation

struct NightscoutPreferences: JSON {
    var report = "preferences"
    let preferences: Preferences?
    let enteredBy: String
}
