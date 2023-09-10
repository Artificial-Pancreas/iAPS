import Foundation

struct NightscoutPreferences: JSON {
    let report = "preferences"
    let preferences: Preferences?
    let useAutotune: Bool?
    let onlyAutotuneBasals: Bool?
}
