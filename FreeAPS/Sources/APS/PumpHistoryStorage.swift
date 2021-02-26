import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryStorage {
    func storePumpEvents(_ events: [NewPumpEvent])
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    @Injected() private var storage: FileStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storePumpEvents(_ events: [NewPumpEvent]) {
        processQueue.async {
            let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
                let id = event.raw.md5String
                switch event.type {
                case .bolus:
                    print("[PUMP EVENT] Bolus event:\n\(event.title))")
                    guard let dose = event.dose else { return [] }
                    let amount = Decimal(string: dose.unitsInDeliverableIncrements.description)
                    return [PumpHistoryEvent(
                        id: id,
                        type: .bolus,
                        timestamp: event.date,
                        amount: amount,
                        duration: nil,
                        durationMin: nil,
                        rate: nil,
                        temp: nil
                    )]
                case .tempBasal:
                    print("[PUMP EVENT] Temp basal event:\n\(event.title))")
                    guard let dose = event.dose else { return [] }
                    let rate = Decimal(string: dose.unitsPerHour.description)
                    let minutes = Int((dose.endDate - dose.startDate).timeInterval / 60)
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .tempBasalDuration,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: minutes,
                            rate: rate,
                            temp: nil
                        ),
                        PumpHistoryEvent(
                            id: "_" + id,
                            type: .tempBasal,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: rate,
                            temp: .absolute
                        )
                    ]
                case .suspend:
                    print("[PUMP EVENT] Suspend event:\n\(event.title))")
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpSuspend,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil
                        )
                    ]
                case .resume:
                    print("[PUMP EVENT] Resume event:\n\(event.title))")
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpResume,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil
                        )
                    ]
                case .rewind:
                    print("[PUMP EVENT] Rewind event:\n\(event.title))")
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .rewind,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil
                        )
                    ]
                case .prime:
                    print("[PUMP EVENT] Prime event:\n\(event.title))")
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .prime,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil
                        )
                    ]
                default:
                    return []
                }
            }

            self.processNewEvents(eventsToStore)
        }
    }

    private func processNewEvents(_ events: [PumpHistoryEvent]) {
        dispatchPrecondition(condition: .onQueue(processQueue))
        try? storage.transaction { storage in
            try storage.append(events, to: OpenAPS.Monitor.pumpHistory, uniqBy: \.id)
            let uniqEvents = try storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)
                .filter { $0.timestamp.addingTimeInterval(1.days.timeInterval) > Date() }
                .sorted { $0.timestamp > $1.timestamp }
            print("[HISTORY] New Events\n\(uniqEvents)")
            try storage.save(Array(uniqEvents), as: OpenAPS.Monitor.pumpHistory)
        }
    }
}
