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
    /// on the first two-digit patch release. A leading "v" and a "-rc1"/"+build" suffix are
    /// ignored; anything else that is not numeric makes the answer "not newer".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(of: candidate), let b = components(of: current) else { return false }
        for i in 0 ..< max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// "v8.3.9-rc1" → [8, 3, 9]; nil when a component is not a number.
    private static func components(of version: String) -> [Int]? {
        var core = version.trimmingCharacters(in: .whitespaces)
        if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
        if let cut = core.firstIndex(where: { $0 == "-" || $0 == "+" || $0 == " " }) {
            core = String(core[..<cut])
        }
        guard !core.isEmpty else { return nil }
        let fields = core.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = fields.compactMap { Int($0) }
        return numbers.count == fields.count ? numbers : nil
    }

    /// The branch this build was made from, as the build phase wrote it into branch.txt
    /// ("dev 81a532e" → "dev"). Read once; nil when branch.txt is missing.
    static let runningBranchName: String? = Bundle.main.gitBranch?
        .split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)

    /// The published version a build on `running` should be told about, or nil when there
    /// is nothing newer for it:
    /// - a build from `main` (or `master`) is compared with the published main version,
    /// - a build from `dev` with the published dev version,
    /// - any other branch (a feature branch or fork, cut from either) only with a version
    ///   that BOTH channels have reached — the lower of the two — so a dev-based branch is
    ///   not sent to a main hotfix that is behind its code, nor a main-based one to dev.
    func offered(for running: String, branch: String?) -> String? {
        let candidate: String
        switch branch {
        case "main",
             "master":
            candidate = main
        case "dev":
            candidate = dev
        default:
            let published = [main, dev].filter { !$0.isEmpty }
            guard let first = published.first else { return nil }
            candidate = published.count == 2 && Version.isNewer(main, than: dev) ? dev : first
        }
        guard !candidate.isEmpty, Version.isNewer(candidate, than: running) else { return nil }
        return candidate
    }
}
