import Combine
import Foundation

struct AppGroupSource: GlucoseSource {
    let from: String

    func fetch() -> AnyPublisher<[BloodGlucose], Never> {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return Just([]).eraseToAnyPublisher()
        }

        return Just(fetchLastBGs(60, sharedDefaults)).eraseToAnyPublisher()
    }

    private func fetchLastBGs(_ count: Int, _ sharedDefaults: UserDefaults) -> [BloodGlucose] {
        guard let sharedData = sharedDefaults.data(forKey: "latestReadings") else {
            return []
        }

        let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])
        guard let sgvs = decoded as? [AnyObject] else {
            return []
        }

        var results: [BloodGlucose] = []
        for sgv in sgvs.prefix(count) {
            guard
                let glucose = sgv["Value"] as? Int,
                let direction = sgv["direction"] as? String,
                let timestamp = sgv["DT"] as? String,
                let date = parseDate(timestamp)
            else { continue }

            if let from = sgv["from"] as? String {
                guard from == self.from else { continue }
            }

            results.append(
                BloodGlucose(
                    sgv: glucose,
                    direction: BloodGlucose.Direction(rawValue: direction),
                    date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                    dateString: date,
                    unfiltered: nil,
                    filtered: nil,
                    noise: nil,
                    glucose: glucose,
                    type: "sgv"
                )
            )
        }
        return results
    }

    private func parseDate(_ timestamp: String) -> Date? {
        // timestamp looks like "/Date(1462404576000)/"
        guard let re = try? NSRegularExpression(pattern: "\\((.*)\\)"),
              let match = re.firstMatch(in: timestamp, range: NSMakeRange(0, timestamp.count))
        else {
            return nil
        }

        let matchRange = match.range(at: 1)
        let epoch = Double((timestamp as NSString).substring(with: matchRange))! / 1000
        return Date(timeIntervalSince1970: epoch)
    }

    func sourceInfo() -> [String: Any]? {
        [GlucoseSourceKey.description.rawValue: "Group ID: \(Bundle.main.appGroupSuiteName ?? "Not set"))"]
    }
}

public extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
