import Foundation
import SwiftDate
import Swinject

protocol GlucoseStorage {
    func storeGlucose(_ glucose: [BloodGlucose])
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeGlucose(_ glucose: [BloodGlucose]) {
        processQueue.async {
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
}
