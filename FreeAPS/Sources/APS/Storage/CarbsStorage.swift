import Foundation
import SwiftDate
import Swinject

protocol CarbsObserver {
    func carbsDidUpdate(_ carbs: [CarbsEntry])
}

protocol CarbsStorage {
    func storeCarbs(_ carbs: [CarbsEntry])
    func syncDate() -> Date
    func recent() -> [CarbsEntry]
    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment]
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ carbs: [CarbsEntry]) {
        processQueue.sync {
            let file = OpenAPS.Monitor.carbHistory
            var uniqEvents: [CarbsEntry] = []
            try? self.storage.transaction { storage in
                try storage.append(carbs, to: file, uniqBy: \.createdAt)
                uniqEvents = try storage.retrieve(file, as: [CarbsEntry].self)
                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.createdAt > $1.createdAt }
                try storage.save(Array(uniqEvents), as: file)
            }
            broadcaster.notify(CarbsObserver.self, on: processQueue) {
                $0.carbsDidUpdate(uniqEvents)
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

    func recent() -> [CarbsEntry] {
        (try? storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self))?.reversed() ?? []
    }

    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = (try? storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NigtscoutTreatment].self)) ?? []

        let eventsManual = recent().filter { $0.enteredBy == CarbsEntry.manual }
        let treatments = eventsManual.map {
            NigtscoutTreatment(
                duration: nil,
                rawDuration: nil,
                rawRate: nil,
                absolute: nil,
                rate: nil,
                eventType: .nsCarbCorrection,
                createdAt: $0.createdAt,
                entededBy: CarbsEntry.manual,
                bolus: nil,
                insulin: nil,
                notes: nil,
                carbs: $0.carbs,
                targetTop: nil,
                targetBottom: nil
            )
        }
        return Array(Set(treatments).subtracting(Set(uploaded)))
    }
}
