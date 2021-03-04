import Foundation
import SwiftDate
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose])
    func syncDate() -> Date
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!

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
                try storage.save(Array(uniqEvents), as: file)
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
}
