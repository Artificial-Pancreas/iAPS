import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }

    var buildDate: Date {
        if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let infoAttr = try? FileManager.default.attributesOfItem(atPath: infoPath),
           let infoDate = infoAttr[.modificationDate] as? Date
        {
            return infoDate
        }
        return Date()
    }

    var plist_prefs: PlistPreferences {
        let url = Bundle.main.url(forResource: "Preferences", withExtension: "plist")!
        let data = try! Data(contentsOf: url)
        return try! PropertyListDecoder().decode(PlistPreferences.self, from: data)
    }
}
