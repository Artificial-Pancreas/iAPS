import Combine
import Foundation
import HealthKit
import LibreTransmitter
import LoopKit
import LoopKitUI
import Swinject

// ----------------------------------------

//    xDrip payload example:
//    --------------
//    DT = "/Date(1757767879000)/";
//    ST = "/Date(1757767879000)/";
//    Trend = 5;
//    Value = 106;
//    direction = FortyFiveDown;
//    from = xDrip;

final class AppGroupSource {
    private(set) var latestReadingFrom: AppGroupSourceType?
    private(set) var latestReadingFromOther: String?
    private(set) var latestReadingDate: Date?
    private(set) var deviceAddress: String?

    private var _heartBeatDelegate: AppGroupCGMHeartBeatDelegate?

    var heartBeatDelegate: AppGroupCGMHeartBeatDelegate? {
        set {
            _heartBeatDelegate = newValue
            if newValue == nil {
                debug(.nightscout, "AppGroupSource - stopping heartbeat")
                HeartBeatManager.shared.disconnectBluetoothTransmitter()
            }
        }
        get {
            _heartBeatDelegate
        }
    }

    func fetch() -> CGMReadingResult {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return .noData
        }

        return fetchLastBGs(60, sharedDefaults)
    }

    private var previouslySeenSharedData: Data?

    private func fetchLastBGs(_ count: Int, _ sharedDefaults: UserDefaults) -> CGMReadingResult {
        guard let sharedData = sharedDefaults.data(forKey: "latestReadings"),
              previouslySeenSharedData != sharedData // don't do anything if nothing changed since the last heartbeat
        else {
            return .noData
        }
        previouslySeenSharedData = sharedData

        // make sure HeartBeatManager is setup, it will be firing our timer on BT activity
        deviceAddress = HeartBeatManager.shared.checkCGMBluetoothTransmitter(
            sharedUserDefaults: sharedDefaults,
            heartbeat: _heartBeatDelegate
        )
        let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])
        guard let sgvs = decoded as? [AnyObject] else {
            return .noData
        }

        guard let first = sgvs.first,
              let firstFrom = first["from"] as? String
        else {
            latestReadingFrom = nil
            latestReadingFromOther = nil
            return .noData
        }

        // keep track of the app we're reading from
        latestReadingFrom = .parseFromValue(firstFrom)
        if latestReadingFrom == nil {
            latestReadingFromOther = firstFrom
        } else {
            latestReadingFromOther = nil
        }

        var results: [NewGlucoseSample] = []

        for sgv in sgvs.prefix(count) {
            guard
                let from = sgv["from"] as? String,
                from == firstFrom,
                let glucose = sgv["Value"] as? Int,
                let timestamp = sgv["DT"] as? String,
                let date = parseDate(timestamp)
            else { continue }

//            var direction: BloodGlucose.Direction?
//
//            // Dexcom changed the format of trend in 2021 so we accept both String/Int types
//            if let directionString = sgv["direction"] as? String {
//                direction = .init(rawValue: directionString)
//            } else if let intTrend = sgv["trend"] as? Int {
//                direction = .init(trendType: GlucoseTrend(rawValue: intTrend))
//            } else if let intTrend = sgv["Trend"] as? Int {
//                direction = .init(trendType: GlucoseTrend(rawValue: intTrend))
//            } else if let stringTrend = sgv["trend"] as? String, let intTrend = Int(stringTrend) {
//                direction = .init(trendType: GlucoseTrend(rawValue: intTrend))
//            }

            results.append(
                NewGlucoseSample(
                    date: date,
                    quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose)),
                    condition: nil,
                    trend: nil, // TODO: add trend?
                    trendRate: nil, // TODO: add trend rate?
                    isDisplayOnly: false,
                    wasUserEntered: false,
                    syncIdentifier: "\(Int(date.timeIntervalSince1970))",
                )
            )
        }
        latestReadingDate = results.map(\.date).max()
        return results.isEmpty ? .noData : .newData(results)
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

//    func sourceInfo() -> [String: Any]? {
//        [GlucoseSourceKey.description.rawValue: "Group ID: \(Bundle.main.appGroupSuiteName ?? "Not set"))"]
//    }
}

protocol AppGroupCGMHeartBeatDelegate: AnyObject {
    func heartbeat()
}

public extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}

enum AppGroupSourceType: String, JSON, CaseIterable, Identifiable {
    var id: String { rawValue }

    case xdrip
    case glucoseDirect

    var displayName: String {
        switch self {
        case .xdrip:
            return "xDrip4iOS"
        case .glucoseDirect:
            return "Glucose Direct"
        }
    }

    var appURL: URL? {
        switch self {
        case .xdrip:
            return URL(string: "xdripswift://")!
        case .glucoseDirect:
            return URL(string: "libredirect://")!
        }
    }

    var externalLink: URL? {
        switch self {
        case .xdrip:
            return URL(string: "https://github.com/JohanDegraeve/xdripswift")!
        case .glucoseDirect:
            return URL(string: "https://github.com/creepymonster/GlucoseDirectApp")!
        }
    }

    static func parseFromValue(_ from: String) -> AppGroupSourceType? {
        switch from {
        case "xDrip": .xdrip
        case "GlucoseDirect": .glucoseDirect
        default: nil
        }
    }
}
