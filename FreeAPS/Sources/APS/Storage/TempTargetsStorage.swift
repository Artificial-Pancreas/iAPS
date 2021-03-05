import Foundation
import SwiftDate
import Swinject

protocol TempTargetsStorage {
    func storeTempTargets(_ targets: [TempTarget])
    func syncDate() -> Date
}

final class BaseTempTargetsStorage: TempTargetsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseTempTargetsStorage.processQueue")
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeTempTargets(_ targets: [TempTarget]) {
        processQueue.sync {
            let file = OpenAPS.Settings.tempTargets
            try? self.storage.transaction { storage in
                try storage.append(targets, to: file, uniqBy: \.createdAt)
                let uniqEvents = try storage.retrieve(file, as: [TempTarget].self)
                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.createdAt > $1.createdAt }
                try storage.save(Array(uniqEvents), as: file)
            }
        }
    }

    func syncDate() -> Date {
        guard let events = try? storage.retrieve(OpenAPS.Settings.tempTargets, as: [TempTarget].self),
              let recent = events.filter({ $0.enteredBy != TempTarget.manual }).first
        else {
            return Date().addingTimeInterval(-1.days.timeInterval)
        }
        return recent.createdAt.addingTimeInterval(-6.minutes.timeInterval)
    }
}
