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
            try? self.storage.transaction { storage in
                try storage.append(glucose, to: OpenAPS.Monitor.glucose, uniqBy: \.date)
                let uniqEvents = try storage.retrieve(OpenAPS.Monitor.glucose, as: [BloodGlucose].self)
                    .filter { $0.dateString.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.dateString > $1.dateString }
                print("[GLUCOSE] New Events\n\(uniqEvents)")
                try storage.save(Array(uniqEvents), as: OpenAPS.Monitor.glucose)
            }
        }
    }
}
