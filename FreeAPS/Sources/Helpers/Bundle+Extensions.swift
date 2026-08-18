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

    var profileExpiration: String? {
        guard
            let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
            let profileData = try? Data(contentsOf: URL(fileURLWithPath: profilePath)),
            // Note: We use `NSString` instead of `String`, because it makes it easier working with regex, ranges, substring etc.
            let profileNSString = NSString(data: profileData, encoding: String.Encoding.ascii.rawValue)
        else {
            print(
                "WARNING: Could not find or read `embedded.mobileprovision`. If running on Simulator, there are no provisioning profiles."
            )
            return nil
        }

        // NOTE: We have the `[\\W]*?` check to make sure that variations in number of tabs or new lines in the future does not influence the result.
        guard let regex = try? NSRegularExpression(pattern: "<key>ExpirationDate</key>[\\W]*?<date>(.*?)</date>", options: [])
        else {
            print("Warning: Could not create regex.")
            return nil
        }

        let regExMatches = regex.matches(
            in: profileNSString as String,
            options: [],
            range: NSRange(location: 0, length: profileNSString.length)
        )

        // NOTE: range `0` corresponds to the full regex match, so to get the first capture group, we use range `1`
        guard let rangeOfCapturedGroupForDate = regExMatches.first?.range(at: 1) else {
            print("Warning: Could not find regex match or capture group.")
            return nil
        }

        let dateWithTimeAsString = profileNSString.substring(with: rangeOfCapturedGroupForDate)

        guard let dateAsStringIndex = dateWithTimeAsString.firstIndex(of: "T") else {
            return nil
        }
        return String(dateWithTimeAsString[..<dateAsStringIndex])
    }
}
