import Foundation
import LoopKit
import SwiftDate
import Swinject

extension NewPumpEvent: @retroactive @unchecked Sendable {}

protocol PumpHistoryStorage: Sendable {
    func storeEvents(_ events: [PumpHistoryEvent]) async
    func recent() async -> [PumpHistoryEvent]
    func saveCancelTempEvents() async
    func deleteInsulin(at date: Date) async
}

actor BasePumpHistoryStorage: PumpHistoryStorage, LifetimeOwner, AppService {
    private let storage: FileStorage
    private let appCoordinator: AppCoordinator

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
        observe(appCoordinator.pumpEvents) { me, events in
            await me.storePumpEvents(events)
        }
    }

    private var concentration: (concentration: Double, increment: Double) {
        get async {
            await coreDataStorage.insulinConcentration()
        }
    }

    func storePumpEvents(_ events: [NewPumpEvent]) async {
        guard !events.isEmpty else { return }

        let insulinConcentration = await concentration
        let storedEvents = await self.recent()
        let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
            let id = event.raw.md5String
            switch event.type {
            case .bolus:
                guard let dose = event.dose else { return [] }
                var amount = Decimal(string: dose.unitsInDeliverableIncrements.description)

                if insulinConcentration.concentration != 1, var needingAdjustment = amount {
                    needingAdjustment *= Decimal(insulinConcentration.concentration)
                    amount = needingAdjustment
                        .roundBolusIncrements(increment: insulinConcentration.concentration * 0.05)
                }

                let minutes = Int((dose.endDate - dose.startDate).timeInterval / 60)
                if let duplicatedEvent = storedEvents
                    .first(where: { x in
                        Int(x.timestamp.timeIntervalSince1970) == Int(event.date.timeIntervalSince1970) && x.type == .bolus })
                {
                    return [PumpHistoryEvent(
                        id: duplicatedEvent.id,
                        type: .bolus,
                        timestamp: duplicatedEvent.timestamp,
                        amount: amount,
                        duration: minutes,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        isSMB: dose.automatic,
                        isExternal: dose.manuallyEntered
                    )]
                }

                return [PumpHistoryEvent(
                    id: id,
                    type: .bolus,
                    timestamp: event.date,
                    amount: amount,
                    duration: minutes,
                    durationMin: nil,
                    rate: nil,
                    temp: nil,
                    carbInput: nil,
                    isSMB: dose.automatic,
                    isExternal: dose.manuallyEntered
                )]
            case .tempBasal:
                guard let dose = event.dose else { return [] }
                var rate = Decimal(dose.unitsPerHour)

                // Eventual adjustment for concentration
                if insulinConcentration.concentration != 1, rate >= 0.05 {
                    rate *= Decimal(insulinConcentration.concentration)
                    rate = rate.roundBolusIncrements(increment: insulinConcentration.concentration * 0.05)
                }

                let minutes = (dose.endDate - dose.startDate).timeInterval / 60
                let delivered = dose.deliveredUnits
                let date = event.date

                let isCancel = delivered != nil //! event.isMutable && delivered != nil
                guard !isCancel else { return [] }

                return [
                    PumpHistoryEvent(
                        id: id,
                        type: .tempBasalDuration,
                        timestamp: date,
                        amount: nil,
                        duration: nil,
                        durationMin: Int(round(minutes)),
                        rate: nil,
                        temp: nil,
                        carbInput: nil
                    ),
                    PumpHistoryEvent(
                        id: "_" + id,
                        type: .tempBasal,
                        timestamp: date,
                        amount: nil,
                        duration: nil,
                        durationMin: nil,
                        rate: rate,
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

        await self.storeEvents(eventsToStore)
    }

    func storeEvents(_ events: [PumpHistoryEvent]) async {
        let file = OpenAPS.Monitor.pumpHistory
        let uniqEvents: [PumpHistoryEvent] = await self.storage.appendAndModify(events, to: file, uniqBy: \.id) {
            $0
                .filter { $0.timestamp.addingTimeInterval(1.days.timeInterval) > Date() }
                .sorted { $0.timestamp > $1.timestamp }
        }
        // oldest -> newest
        self.appCoordinator.sendPumpHistoryUpdate(uniqEvents.reversed())
    }

    /// oldest -> newest
    func recent() async -> [PumpHistoryEvent] {
        await storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)?.reversed() ?? []
    }

    func deleteInsulin(at date: Date) async {
        let (didModify, updatedValues) = await storage
            .maybeModify(file: OpenAPS.Monitor.pumpHistory, as: PumpHistoryEvent.self) { inStorage in
                var allValues = inStorage
                guard let entryIndex = allValues.firstIndex(where: { $0.timestamp == date }) else {
                    return nil // do not modify
                }
                allValues.remove(at: entryIndex)
                return allValues
            }
        if didModify {
            // oldest -> newest
            self.appCoordinator.sendPumpHistoryUpdate(updatedValues.reversed())
        }
    }

    func saveCancelTempEvents() async {
        let basalID = UUID().uuidString
        let date = Date()

        let events = [
            PumpHistoryEvent(
                id: basalID,
                type: .tempBasalDuration,
                timestamp: date,
                amount: nil,
                duration: nil,
                durationMin: 0,
                rate: nil,
                temp: nil,
                carbInput: nil
            ),
            PumpHistoryEvent(
                id: "_" + basalID,
                type: .tempBasal,
                timestamp: date,
                amount: nil,
                duration: nil,
                durationMin: nil,
                rate: 0,
                temp: .absolute,
                carbInput: nil
            )
        ]

        await storeEvents(events)
    }
}
