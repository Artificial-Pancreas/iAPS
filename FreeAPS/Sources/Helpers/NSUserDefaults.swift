import Foundation
// import SwiftUI // Import SwiftUI if you are using the SwiftUI App lifecycle or @AppStorage

class AppSettings {
    static let shared = AppSettings() // Singleton instance for easy access

    private init() {
        registerDefaultsFromSettingsBundle()
    }

    func registerDefaultsFromSettingsBundle() {
        if let settingsURL = Bundle.main.url(forResource: "Root", withExtension: "plist", subdirectory: "Settings.bundle"),
           let settingsDict = NSDictionary(contentsOf: settingsURL) as? [String: Any],
           let preferences = settingsDict["PreferenceSpecifiers"] as? [[String: Any]]
        {
            var defaultsToRegister = [String: Any]()
            for preference in preferences {
                // Extract the "Key" and "DefaultValue" for each setting.
                if let key = preference["Key"] as? String,
                   let defaultValue = preference["DefaultValue"]
                {
                    defaultsToRegister[key] = defaultValue
                }
            }
            UserDefaults.standard.register(defaults: defaultsToRegister)
            print("Successfully registered default settings from Root.plist.")
        } else {
            print("Error: Could not find or parse Root.plist in Settings.bundle.")
        }
    }

    var hideSettingsToggle: Bool {
        UserDefaults.standard.bool(forKey: "hide_settings_toggle")
    }
}
