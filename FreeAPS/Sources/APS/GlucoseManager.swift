import Combine
import Foundation
import SwiftDate
import Swinject

protocol GlucoseManager {}

final class BaseGlucoseManager: GlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")
    @Injected() var glucoseStogare: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var apsManager: APSManager!

    private var lifetime = Set<AnyCancellable>()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)

    init(resolver: Resolver) {
        injectServices(resolver)
        subscribe()
    }

    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { date -> AnyPublisher<(Date, Date, [BloodGlucose]), Never> in
                debug(.nightscout, "Glucose manager heartbeat")
                debug(.nightscout, "Start fetching glucose")
                return Publishers.CombineLatest3(
                    Just(date),
                    Just(self.glucoseStogare.syncDate()),
                    Publishers.CombineLatest(
                        self.nightscoutManager.fetchGlucose(),
                        self.fetchGlucoseFromSgaredGroup()
                    )
                    .map { [$0, $1].flatMap { $0 } }
                    .eraseToAnyPublisher()
                )
                .eraseToAnyPublisher()
            }
            .sink { date, syncDate, glucose in
                // Because of Spike dosn't respect a date query
                let filteredByDate = glucose.filter { $0.dateString > syncDate }
                let filtered = self.glucoseStogare.filterTooFrequentGlucose(filteredByDate, at: syncDate)
                if !filtered.isEmpty {
                    debug(.nightscout, "New glucose found")
                    self.apsManager.heartbeat(date: date, force: true)
                }
            }
            .store(in: &lifetime)
        timer.resume()
    }

    private func fetchGlucoseFromSgaredGroup() -> AnyPublisher<[BloodGlucose], Never> {
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

            results.append(
                BloodGlucose(
                    _id: UUID().uuidString,
                    sgv: glucose,
                    direction: BloodGlucose.Direction(rawValue: direction),
                    date: Decimal(Int(date.timeIntervalSince1970 * 1000)),
                    dateString: date,
                    filtered: nil,
                    noise: nil,
                    glucose: glucose
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
}

public extension Bundle {
    var appGroupSuiteName: String? {
        object(forInfoDictionaryKey: "AppGroupID") as? String
    }
}
