import Foundation
import SwiftDate
import Swinject

protocol CarbsStorage {
    func storeCarbs(_ carbs: [CarbsEntry])
    func syncDate() -> Date
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ carbs: [CarbsEntry]) {
        processQueue.sync {
            let file = OpenAPS.Monitor.carbHistory
            try? self.storage.transaction { storage in
                try storage.append(carbs, to: file, uniqBy: \.createdAt)
                let uniqEvents = try storage.retrieve(file, as: [CarbsEntry].self)
                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.createdAt > $1.createdAt }
                try storage.save(Array(uniqEvents), as: file)
            }
        }
    }

    func syncDate() -> Date {
        guard let events = try? storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self),
              let recent = events.filter({ $0.enteredBy != CarbsEntry.manual }).first
        else {
            return Date().addingTimeInterval(-1.days.timeInterval)
        }
        return recent.createdAt.addingTimeInterval(-6.minutes.timeInterval)
    }
}
