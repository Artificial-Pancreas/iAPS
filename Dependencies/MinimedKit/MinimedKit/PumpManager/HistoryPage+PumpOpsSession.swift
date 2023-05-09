//
//  HistoryPage+PumpOpsSession.swift
//  RileyLinkKit
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//


extension HistoryPage {
    /// Returns TimestampedHistoryEvents from this page occuring after a given date
    ///
    /// - Parameters:
    ///   - start: The date to filter events occuring on or after
    ///   - timeZone: The current time zone offset of the pump
    ///   - model: The pump model
    /// - Returns: A tuple containing:
    ///     - events: The matching events
    ///     - hasMoreEvents: Whether the next page likely contains events after the specified start date
    ///     - cancelledEarly:
    func timestampedEvents(after start: Date, timeZone: TimeZone, model: PumpModel) -> (events: [TimestampedHistoryEvent], hasMoreEvents: Bool, cancelledEarly: Bool) {
        // Start with some time in the future, to account for the condition when the pump's clock is ahead
        // of ours by a small amount.
        var timeCursor = Date(timeIntervalSinceNow: TimeInterval(minutes: 60))
        var events = [TimestampedHistoryEvent]()
        var timeAdjustmentInterval: TimeInterval = 0
        var seenEventData = Set<Data>()
        var lastEvent: PumpEvent?

        for event in self.events.reversed() {
            if let event = event as? TimestampedPumpEvent, !seenEventData.contains(event.rawData) {
                seenEventData.insert(event.rawData)

                var timestamp = event.timestamp
                timestamp.timeZone = timeZone

                if let changeTimeEvent = event as? ChangeTimePumpEvent, let newTimeEvent = lastEvent as? NewTimePumpEvent {
                    timeAdjustmentInterval += (newTimeEvent.timestamp.date?.timeIntervalSince(changeTimeEvent.timestamp.date!))!
                }
                
                if let alarm = event as? PumpAlarmPumpEvent, alarm.alarmType.indicatesUnrecoverableClockIssue {
                    NSLog("Found device reset battery issue in history (%@). Ending history fetch.", String(describing: event))
                    return (events: events, hasMoreEvents: false, cancelledEarly: true)
                }

                if let date = timestamp.date?.addingTimeInterval(timeAdjustmentInterval) {

                    let shouldCheckDateForCompletion = !event.isDelayedAppend(with: model)

                    if shouldCheckDateForCompletion {
                        if date <= start {
                            // Success, we have all the events we need
                            //NSLog("Found event at or before startDate(%@)", date as NSDate, String(describing: eventTimestampDeltaAllowance), startDate as NSDate)
                            return (events: events, hasMoreEvents: false, cancelledEarly: false)
                        } else if date.timeIntervalSince(timeCursor) > TimeInterval(minutes: 60) {
                            // Appears that pump lost time; we can't build up a valid timeline from this point back.
                            // TODO: Convert logging
                            NSLog("Found event (%@) out of order in history. Ending history fetch.", date as NSDate)
                            return (events: events, hasMoreEvents: false, cancelledEarly: true)
                        }

                        timeCursor = date
                    }

                    events.insert(TimestampedHistoryEvent(pumpEvent: event, date: date), at: 0)
                }
            }

            lastEvent = event
        }

        return (events: events, hasMoreEvents: true, cancelledEarly: false)
    }
}

extension PumpAlarmType {
    var indicatesUnrecoverableClockIssue: Bool {
        switch self {
        case .deviceResetBatteryIssue17, .deviceResetBatteryIssue21:
            return true
        default:
            return false
        }
        
    }
}
