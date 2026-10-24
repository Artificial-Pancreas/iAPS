import Foundation

struct Version: JSON, Decodable {
    var main: String
    var dev: String
}

extension Version {
    private enum CodingKeys: String, CodingKey {
        case main
        case dev
    }
}

extension Version {
    /// Component-wise numeric comparison: "8.3.10" is newer than "8.3.8". A plain string
    /// compare says the opposite, which is how the Settings reminder would have gone quiet
    /// on the first two-digit patch release.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0 ..< max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The version a build on `current` should be told about, or nil when it is up to date:
    /// `dev` for builds from the dev branch, `main` for everything else.
    func newer(than current: String, onDevBranch: Bool) -> String? {
        let published = onDevBranch ? dev : main
        guard !published.isEmpty, Version.isNewer(published, than: current) else { return nil }
        return published
    }
}
