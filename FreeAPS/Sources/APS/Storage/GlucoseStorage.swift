import Foundation
import SwiftDate
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose])
    func recent() -> [BloodGlucose]
    func syncDate() -> Date
    func filterTooFrequentGlucose(_ glucose: [BloodGlucose]) -> [BloodGlucose]
    func lastGlucoseDate() -> Date
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    private enum Config {
        static let filterTime: TimeInterval = 4.75 * 60
    }

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeGlucose(_ glucose: [BloodGlucose]) {
        processQueue.sync {
            let filtered = self.filterTooFrequentGlucose(glucose)
            let file = OpenAPS.Monitor.glucose
            self.storage.transaction { storage in
                storage.append(filtered, to: file, uniqBy: \.dateString)
                let uniqEvents = storage.retrieve(file, as: [BloodGlucose].self)?
                    .filter { $0.dateString.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.dateString > $1.dateString } ?? []
                let glucose = Array(uniqEvents)
                storage.save(glucose, as: file)

                DispatchQueue.main.async {
                    self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate(glucose.reversed())
                    }
                }
            }
        }
    }

    func syncDate() -> Date {
        guard let events = storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self),
              let recent = events.first
        else {
            return Date().addingTimeInterval(-1.days.timeInterval)
        }
        return recent.dateString.addingTimeInterval(Config.filterTime)
    }

    func recent() -> [BloodGlucose] {
        storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)?.reversed() ?? []
    }

    func lastGlucoseDate() -> Date {
        recent().last?.dateString ?? .distantPast
    }

    func filterTooFrequentGlucose(_ glucose: [BloodGlucose]) -> [BloodGlucose] {
        var lastDate = lastGlucoseDate()
        var filtered: [BloodGlucose] = []

        for entry in glucose.reversed() {
            guard entry.dateString.addingTimeInterval(-Config.filterTime) > lastDate else {
                continue
            }
            filtered.append(entry)
            lastDate = entry.dateString
        }

        return filtered
    }
}

protocol GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose])
}
