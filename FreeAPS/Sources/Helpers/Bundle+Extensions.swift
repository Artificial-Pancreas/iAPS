import Foundation

extension Bundle {
    var releaseVersionNumber: String? {
        infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var buildVersionNumber: String? {
        infoDictionary?["CFBundleVersion"] as? String
    }

    /// "<branch-or-tag> <short sha>" as written into branch.txt by the build phase
    /// (e.g. "dev 81a532e"). The commit is the identity of the code that is running —
    /// build numbers are per-builder counters and version alone spans many commits.
    /// Nil when branch.txt is missing or malformed.
    var gitBranch: String? {
        guard let url = url(forResource: "branch", withExtension: "txt"),
              let content = try? String(contentsOf: url)
        else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "=")
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "BRANCH"
            else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
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

    // MARK: - Embedded provisioning profile

    /// The embedded provisioning profile as ASCII text. It is a CMS-wrapped plist, so the XML is
    /// read with regexes rather than a plist decoder. Nil on the Simulator (no profile).
    private static let embeddedProvisioningProfile: String? = {
        guard
            let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
            let profileData = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
            // `NSString` makes the regex / range / substring work below straightforward.
            let profile = NSString(data: profileData, encoding: String.Encoding.ascii.rawValue)
        else {
            print(
                "WARNING: Could not find or read `embedded.mobileprovision`. If running on Simulator, there are no provisioning profiles."
            )
            return nil
        }
        return profile as String
    }()

    /// When the embedded provisioning profile stops being valid. Nil without a profile.
    /// Read once: the profile does not change while the process runs.
    private static let cachedProfileExpirationDate: Date? = {
        guard let profile = embeddedProvisioningProfile.map({ $0 as NSString }),
              // `[\W]*?` absorbs whatever whitespace sits between the key and its value.
              let regex = try? NSRegularExpression(pattern: "<key>ExpirationDate</key>[\\W]*?<date>(.*?)</date>", options: [])
        else { return nil }

        let matches = regex.matches(in: profile as String, options: [], range: NSRange(location: 0, length: profile.length))
        // Range 0 is the whole match; range 1 the captured ISO-8601 date.
        guard let range = matches.first?.range(at: 1) else {
            print("Warning: Could not find the profile's ExpirationDate.")
            return nil
        }
        return ISO8601DateFormatter().date(from: profile.substring(with: range))
    }()

    var profileExpirationDate: Date? {
        Self.cachedProfileExpirationDate
    }

    /// The profile's expiry as "yyyy-MM-dd" (what the Settings header has always shown).
    var profileExpiration: String? {
        guard let date = profileExpirationDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// True when the embedded profile is tied to particular devices (development / ad-hoc,
    /// `ProvisionedDevices`) or to a whole organisation (in-house, `ProvisionsAllDevices`). Such a
    /// build — installed by Xcode or sideloaded — runs exactly as long as its profile. App Store and
    /// TestFlight profiles list no devices; their lifetime is TestFlight's 90 days instead.
    var profileProvisionsSpecificDevices: Bool {
        Self.cachedProfileProvisionsSpecificDevices
    }

    private static let cachedProfileProvisionsSpecificDevices: Bool = {
        guard let profile = embeddedProvisioningProfile.map({ $0 as NSString }) else { return false }
        if profile.range(of: "<key>ProvisionedDevices</key>").location != NSNotFound {
            return true
        }
        guard let regex = try? NSRegularExpression(pattern: "<key>ProvisionsAllDevices</key>[\\W]*?<true/>", options: [])
        else { return false }
        return regex.firstMatch(in: profile as String, options: [], range: NSRange(location: 0, length: profile.length)) != nil
    }()
}
