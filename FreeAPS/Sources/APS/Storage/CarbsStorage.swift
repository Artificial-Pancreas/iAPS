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
    func deleteCarbs(at date: Date)
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
            self.storage.transaction { storage in
                storage.append(carbs, to: file, uniqBy: \.createdAt)
                uniqEvents = storage.retrieve(file, as: [CarbsEntry].self)?
                    .filter { $0.createdAt.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.createdAt > $1.createdAt } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
            broadcaster.notify(CarbsObserver.self, on: processQueue) {
                $0.carbsDidUpdate(uniqEvents)
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() -> [CarbsEntry] {
        storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)?.reversed() ?? []
    }

    func deleteCarbs(at date: Date) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self) ?? []
            guard let entryIndex = allValues.firstIndex(where: { $0.createdAt == date }) else {
                return
            }
            allValues.remove(at: entryIndex)
            storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
            broadcaster.notify(CarbsObserver.self, on: processQueue) {
                $0.carbsDidUpdate(allValues)
            }
        }
    }

    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment] {
        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NigtscoutTreatment].self) ?? []

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
                enteredBy: CarbsEntry.manual,
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
