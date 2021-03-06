import Foundation
import SwiftDate
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose])
    func recent() -> [BloodGlucose]
    func syncDate() -> Date
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeGlucose(_ glucose: [BloodGlucose]) {
        processQueue.sync {
            let file = OpenAPS.Monitor.glucose
            try? self.storage.transaction { storage in
                try storage.append(glucose, to: file, uniqBy: \.dateString)
                let uniqEvents = try storage.retrieve(file, as: [BloodGlucose].self)
                    .filter { $0.dateString.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.dateString > $1.dateString }
                let glucose = Array(uniqEvents)
                try storage.save(glucose, as: file)

                DispatchQueue.main.async {
                    self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate(glucose.reversed())
                    }
                }
            }
        }
    }

    func syncDate() -> Date {
        guard let events = try? storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self),
              let recent = events.first
        else {
            return Date().addingTimeInterval(-1.days.timeInterval)
        }
        return recent.dateString.addingTimeInterval(-6.minutes.timeInterval)
    }

    func recent() -> [BloodGlucose] {
        (try? storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self))?.reversed() ?? []
    }
}

protocol GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose])
}
