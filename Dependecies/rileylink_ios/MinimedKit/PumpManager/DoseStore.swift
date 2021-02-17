//
//  DoseStore.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKit


// Bridges support for MinimedKit data types
extension Collection where Element == TimestampedHistoryEvent {
    
    func pumpEvents(from model: PumpModel) -> [NewPumpEvent] {
        var events: [NewPumpEvent] = []
        var lastTempBasalAmount: DoseEntry?
        var lastSuspend: DoseEntry?
        // Always assume the sequence may have started rewound. LoopKit will ignore unmatched resume events.
        var isRewound = true
        var title: String
        let now = Date()

        for event in self {
            var dose: DoseEntry?
            var eventType: LoopKit.PumpEventType?

            switch event.pumpEvent {
            case let bolus as BolusNormalPumpEvent:
                let bolusEndDate: Date
                if let lastSuspend = lastSuspend, bolus.programmed != bolus.amount, lastSuspend.startDate > event.date {
                    bolusEndDate = lastSuspend.startDate
                } else if bolus.duration > 0 {
                    bolusEndDate = event.date.addingTimeInterval(bolus.duration)
                } else {
                    bolusEndDate = event.date.addingTimeInterval(model.bolusDeliveryTime(units: bolus.amount))
                }
                dose = DoseEntry(type: .bolus, startDate: event.date, endDate: bolusEndDate, value: bolus.programmed, unit: .units, deliveredUnits: bolus.amount)
            case is SuspendPumpEvent:
                dose = DoseEntry(suspendDate: event.date)
                lastSuspend = dose
            case is ResumePumpEvent:
                dose = DoseEntry(resumeDate: event.date)
            case let temp as TempBasalPumpEvent:
                if case .Absolute = temp.rateType {
                    lastTempBasalAmount = DoseEntry(type: .tempBasal, startDate: event.date, value: temp.rate, unit: .unitsPerHour)
                }
            case let temp as TempBasalDurationPumpEvent:
                if let amount = lastTempBasalAmount, amount.startDate == event.date {
                    dose = DoseEntry(
                        type: .tempBasal,
                        startDate: event.date,
                        endDate: event.date.addingTimeInterval(TimeInterval(minutes: Double(temp.duration))),
                        value: amount.unitsPerHour,
                        unit: .unitsPerHour
                    )
                }
            case let basal as BasalProfileStartPumpEvent:
                dose = DoseEntry(
                    type: .basal,
                    startDate: event.date,
                    // Use the maximum-possible duration for a basal entry; its true duration will be reconciled against other entries.
                    endDate: event.date.addingTimeInterval(.hours(24)),
                    value: basal.scheduleEntry.rate,
                    unit: .unitsPerHour
                )
            case is RewindPumpEvent:
                eventType = .rewind

                /* 
                 No insulin is delivered between the beginning of a rewind until the suggested fixed prime is delivered or cancelled.
 
                 If the fixed prime is cancelled, it is never recorded in history. It is possible to cancel a fixed prime and perform one manually some time later, but basal delivery will have resumed during that period.
                 
                 We take the conservative approach and assume delivery is paused only between the Rewind and the first Prime event.
                 */
                dose = DoseEntry(suspendDate: event.date)
                isRewound = true
            case is PrimePumpEvent:
                eventType = .prime

                if isRewound {
                    isRewound = false
                    dose = DoseEntry(resumeDate: event.date)
                }
            case let alarm as PumpAlarmPumpEvent:
                eventType = .alarm

                if case .noDelivery = alarm.alarmType {
                    dose = DoseEntry(suspendDate: event.date)
                }
                break
            case let alarm as ClearAlarmPumpEvent:
                eventType = .alarmClear

                if case .noDelivery = alarm.alarmType {
                    dose = DoseEntry(resumeDate: event.date)
                }
                break
            default:
                break
            }

            title = String(describing: event.pumpEvent)
            events.append(NewPumpEvent(date: event.date, dose: dose, isMutable: event.isMutable(atDate: now, forPump: model), raw: event.pumpEvent.rawData, title: title, type: eventType))
        }

        return events
    }
}
