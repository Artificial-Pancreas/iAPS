import Foundation
import LoopKit
import SwiftDate
import Swinject

extension NewPumpEvent: @retroactive @unchecked Sendable {}

protocol PumpHistoryStorage: Sendable {
    // from pump manager
    func storePumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool) async throws

    // from UI
    func storeEvents(_ events: [PumpHistoryEvent]) async

    func recent() async -> [PumpHistoryEvent]
    func deleteInsulin(at date: Date) async
}

actor BasePumpHistoryStorage: PumpHistoryStorage, LifetimeOwner, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

    private let serializer = TaskSerializer()

    let lifetime = Lifetime()

    private let coreDataStorage = CoreDataStorage()

    init(
        storage: FileStorage,
        appCoordinator: AppCoordinator
    ) {
        self.storage = storage
        self.appCoordinator = appCoordinator
    }

    // this is called on app start
    func start() async {
        appCoordinator.setPumpHistory(await recent())
    }

    private var concentration: (concentration: Double, increment: Double) {
        get async {
            await coreDataStorage.insulinConcentration()
        }
    }

    /// store events received from the pump manager
    func storePumpEvents(_ events: [NewPumpEvent], replacePendingEvents: Bool) async {
        // ensure no race conditions
        await serializer.run {
            guard !events.isEmpty else { return }

            let insulinConcentration = await concentration
            let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
                let id = event.raw.md5String
                switch event.type {
                case .bolus:
                    guard let dose = event.dose else { return [] }
                    let amount = dose.unitsInDeliverableIncrementsAdjustedForConcentration(insulinConcentration.concentration)
                    let minutes = dose.endDate.timeIntervalSince(dose.startDate) / 60

                    // mutable/updated bolus records will get updated (not re-appended) by the `uniqBy: \.identity` in the doStoreEvents
                    return [PumpHistoryEvent(
                        id: id,
                        type: .bolus,
                        timestamp: event.date,
                        isMutable: dose.isMutable,
                        amount: amount,
                        duration: Decimal(minutes).rounded(to: 1),
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        isSMB: dose.automatic,
                        isExternal: dose.manuallyEntered || dose.wasProgrammedByPumpUI
                    )]
                case .tempBasal:
                    guard let dose = event.dose else { return [] }
                    let rate = dose.unitsPerHourAdjustedForConcentration(insulinConcentration.concentration)

                    let minutes = dose.endDate.timeIntervalSince(dose.startDate) / 60
                    let deliveredUnits = dose.deliveredUnitsAdjustedForConcentration(insulinConcentration.concentration)
                    let date = event.date

                    // deliveredUnits != nil -> TBR finished, we'll update it in the storage
                    // in that case, durationMin will be the actual duration the TBR was running for and the existing TBR will be updated in the pump history

                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .tempBasalDuration,
                            timestamp: date,
                            isMutable: dose.isMutable,
                            amount: nil,
                            duration: nil,
                            // adding 0.1 minutes to avoid tiny gaps between TBRs due to rounding
                            durationMin: Decimal(minutes + 0.1).rounded(to: 1),
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        ),
                        PumpHistoryEvent(
                            id: "_" + id,
                            type: .tempBasal,
                            timestamp: date,
                            isMutable: dose.isMutable,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: rate,
                            deliveredUnits: deliveredUnits,
                            temp: .absolute,
                            carbInput: nil
                        )
                    ]
                case .suspend:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpSuspend,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .resume:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpResume,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .rewind:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .rewind,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .prime:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .prime,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .alarm:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpAlarm,
                            timestamp: event.date,
                            note: event.title
                        )
                    ]
                default:
                    return []
                }
            }

            // do NOT call storeEvents from here - it will deadlock
            await self.doStoreEvents(eventsToStore, replacePendingEvents: replacePendingEvents)
        }
    }

    func storeEvents(_ events: [PumpHistoryEvent]) async {
        // ensure no race conditions
        await serializer.run {
            await doStoreEvents(events, replacePendingEvents: false)
        }
    }

    private func doStoreEvents(_ events: [PumpHistoryEvent], replacePendingEvents: Bool) async {
        let file = OpenAPS.Monitor.pumpHistory
        let uniqEvents = await self.storage.modify(file: file, as: PumpHistoryEvent.self) { values in
            let base = replacePendingEvents ? values.filter { $0.isMutable != true } : values
            let appended = BaseFileStorage.doAppend(events, existingValues: base, uniqBy: \.identity)
            return appended
                .filter { $0.timestamp.addingTimeInterval(1.days.timeInterval) > Date() }
                .sorted { $0.timestamp > $1.timestamp }
        }
        // oldest -> newest
        self.appCoordinator.setPumpHistory(uniqEvents.reversed())
    }

    /// oldest -> newest
    func recent() async -> [PumpHistoryEvent] {
        await storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)?.reversed() ?? []
    }

    func deleteInsulin(at date: Date) async {
        await serializer.run {
            let (updatedValues, deleted: deleted) = await storage
                .delete(file: OpenAPS.Monitor.pumpHistory, as: PumpHistoryEvent.self) {
                    $0.timestamp == date
                }
            if let deleted {
                // oldest -> newest
                self.appCoordinator.setPumpHistory(updatedValues.reversed())
                self.appCoordinator.sendPumpHistoryDeleted(deleted)
            }
        }
    }
}
