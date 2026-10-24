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
        branchFileValue("BRANCH")
    }

    /// When the running build was produced, from the BUILD_DATE the build phase writes into
    /// branch.txt. Older builds have no such key; for those the Info.plist modification time is
    /// used when it is plausible. TestFlight / App Store installs stamp bundle files with a
    /// sentinel mtime (1697-10-17, −2^33 s), which is what used to show up as Build_Date in the
    /// statistics and would push the TestFlight expiry countdown into the past.
    var buildDate: Date {
        if let raw = branchFileValue("BUILD_DATE"),
           let date = ISO8601DateFormatter().date(from: raw)
        {
            return date
        }
        if let infoPath = Bundle.main.path(forResource: "Info", ofType: "plist"),
           let infoAttr = try? FileManager.default.attributesOfItem(atPath: infoPath),
           let infoDate = infoAttr[.modificationDate] as? Date,
           infoDate.timeIntervalSince1970 > 946_684_800 // 2000-01-01: rejects the sentinel
        {
            return infoDate
        }
        return Date()
    }

    /// "KEY = value" lookup in branch.txt (written by the "get branch name and commit ID" build
    /// phase). Nil when the file or key is missing, or the value is empty.
    private func branchFileValue(_ key: String) -> String? {
        guard let url = url(forResource: "branch", withExtension: "txt"),
              let content = try? String(contentsOf: url)
        else { return nil }
        for line in content.components(separatedBy: .newlines) {
            guard let eq = line.firstIndex(of: "="),
                  line[..<eq].trimmingCharacters(in: .whitespaces) == key
            else { continue }
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - Embedded provisioning profile

    /// The embedded provisioning profile as ASCII text. It is a CMS-wrapped plist, so the XML is
    /// read with regexes rather than a plist decoder. Nil on the Simulator (no profile).
    private var embeddedProvisioningProfile: NSString? {
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
        return profile
    }

    /// When the embedded provisioning profile stops being valid. Nil without a profile.
    var profileExpirationDate: Date? {
        guard let profile = embeddedProvisioningProfile,
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
        guard let profile = embeddedProvisioningProfile else { return false }
        if profile.range(of: "<key>ProvisionedDevices</key>").location != NSNotFound {
            return true
        }
        guard let regex = try? NSRegularExpression(pattern: "<key>ProvisionsAllDevices</key>[\\W]*?<true/>", options: [])
        else { return false }
        return regex.firstMatch(in: profile as String, options: [], range: NSRange(location: 0, length: profile.length)) != nil
    }
}
