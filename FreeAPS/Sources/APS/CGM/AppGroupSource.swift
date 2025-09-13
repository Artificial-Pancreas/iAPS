import Combine
import Foundation
import LibreTransmitter
import LoopKit
import LoopKitUI
import Swinject

//    xDrip payload example:
//    --------------
//    DT = "/Date(1757767879000)/";
//    ST = "/Date(1757767879000)/";
//    Trend = 5;
//    Value = 106;
//    direction = FortyFiveDown;
//    from = xDrip;

final class AppGroupSource: SettingsObserver {
    private let processQueue = DispatchQueue(label: "AppGroupSource.processQueue")

    private let settingsManager: SettingsManager
    private let broadcaster: Broadcaster
    private let deviceDataManager: DeviceDataManager

    private var appGroupSourceType: AppGroupSourceType?

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    init(resolver: Resolver) {
        settingsManager = resolver.resolve(SettingsManager.self)!
        broadcaster = resolver.resolve(Broadcaster.self)!
        deviceDataManager = resolver.resolve(DeviceDataManager.self)!

        subscribe()
    }

    private func subscribe() {
        settingsDidChange(settingsManager.settings)
        broadcaster.register(SettingsObserver.self, observer: self)
    }

    // listen to the appGroupSourceType setting and start/stop a heartbeat
    func settingsDidChange(_ settings: FreeAPSSettings) {
        processQueue.sync {
            if settings.appGroupSourceType != self.appGroupSourceType {
                if settings.appGroupSourceType == nil {
                    stopFetching()
                } else {
                    startFetching()
                }
                self.appGroupSourceType = settings.appGroupSourceType
            }
        }
    }

    private func startFetching() {
        debug(.nightscout, "AppGroupSource - starting heartbeat")
        lifetime = [] // cancel the previous one, if any - just in case
        timer.publisher
            .receive(on: processQueue)
            .sink { _ in
                // debug(.nightscout, "AppGroupSource timer heartbeat")
                if let bloodGlucose = self.fetch() {
                    debug(.nightscout, "AppGroupSource found new blood glucose data")
                    self.deviceDataManager.bloodGlucoseReadingsReceived(bloodGlucose: bloodGlucose)
                }
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()
    }

    private func stopFetching() {
        debug(.nightscout, "AppGroupSource - stopping heartbeat")
        lifetime = []
        HeartBeatManager.shared.disconnectBluetoothTransmitter()
    }

    private func fetch() -> [BloodGlucose]? {
        guard let suiteName = Bundle.main.appGroupSuiteName,
              let sharedDefaults = UserDefaults(suiteName: suiteName)
        else {
            return nil
        }

        return fetchLastBGs(60, sharedDefaults)
    }

    private var previouslySeenSharedData: Data?

    private func fetchLastBGs(_ count: Int, _ sharedDefaults: UserDefaults) -> [BloodGlucose]? {
        guard let appGroupSourceType = self.appGroupSourceType,
              let sharedData = sharedDefaults.data(forKey: "latestReadings"),
              previouslySeenSharedData != sharedData // don't do anything if nothing changed since the last heartbeat
        else {
            return nil
        }
        previouslySeenSharedData = sharedData

        // make sure HeartBeatManager is setup, it will be firing our timer on BT activity
        HeartBeatManager.shared.checkCGMBluetoothTransmitter(sharedUserDefaults: sharedDefaults, heartbeat: timer)
//        debug(.deviceManager, "APPGROUP : START FETCH LAST BG ")
        let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])
        guard let sgvs = decoded as? [AnyObject] else {
            return []
        }

        var results: [BloodGlucose] = []

        for sgv in sgvs.prefix(count) {
            guard
                let from = sgv["from"] as? String,
                from == appGroupSourceType.sgvFromValue,
                let glucose = sgv["Value"] as? Int,
                let timestamp = sgv["DT"] as? String,
                let date = parseDate(timestamp)
            else { continue }

            var direction: BloodGlucose.Direction?

            // Dexcom changed the format of trend in 2021 so we accept both String/Int types
            if let directionString = sgv["direction"] as? String {
                direction = .init(rawValue: directionString)
            } else if let intTrend = sgv["trend"] as? Int {
                direction = .init(trendType: GlucoseTrend(rawValue: intTrend))
            } else if let intTrend = sgv["Trend"] as? Int {
                direction = .init(trendType: GlucoseTrend(rawValue: intTrend))
            } else if let stringTrend = sgv["trend"] as? String, let intTrend = Int(stringTrend) {
                direction = .init(trendType: GlucoseTrend(rawValue: intTrend))
            }

            results.append(
                BloodGlucose(
                    sgv: glucose,
                    direction: direction ?? BloodGlucose.Direction.none,
                    date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                    dateString: date,
                    unfiltered: Decimal(glucose),
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

    var sgvFromValue: String {
        switch self {
        case .xdrip:
            return "xDrip"
        case .glucoseDirect:
            return "GlucoseDirect"
        }
    }
}
