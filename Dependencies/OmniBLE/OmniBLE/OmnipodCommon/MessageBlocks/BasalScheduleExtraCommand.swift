//
//  BasalScheduleExtraCommand.swift
//  OmniBLE
//
//  From OmniKit/MessageTransport/MessageBlocks/BasalScheduleExtraCommand.swift
//  Created by Pete Schwamb on 3/30/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

public struct BasalScheduleExtraCommand : MessageBlock {

    public let blockType: MessageBlockType = .basalScheduleExtra
    
    public let acknowledgementBeep: Bool
    public let completionBeep: Bool
    public let programReminderInterval: TimeInterval
    public let currentEntryIndex: UInt8
    public let remainingPulses: Double
    public let delayUntilNextTenthOfPulse: TimeInterval
    public let rateEntries: [RateEntry]

    public var data: Data {
        let beepOptions = (UInt8(programReminderInterval.minutes) & 0x3f) + (completionBeep ? (1<<6) : 0) + (acknowledgementBeep ? (1<<7) : 0)
        var data = Data([
            blockType.rawValue,
            UInt8(8 + rateEntries.count * 6),
            beepOptions,
            currentEntryIndex
            ])
        data.appendBigEndian(UInt16(round(remainingPulses * 10)))
        data.appendBigEndian(UInt32(round(delayUntilNextTenthOfPulse.milliseconds * 1000)))
        for entry in rateEntries {
            data.append(entry.data)
        }
        return data
    }
    
    public init(encodedData: Data) throws {
        if encodedData.count < 14 {
            throw MessageBlockError.notEnoughData
        }
        let length = encodedData[1]
        let numEntries = (length - 8) / 6
        
        acknowledgementBeep = encodedData[2] & (1<<7) != 0
        completionBeep = encodedData[2] & (1<<6) != 0
        programReminderInterval = TimeInterval(minutes: Double(encodedData[2] & 0x3f))

        currentEntryIndex = encodedData[3]
        remainingPulses = Double(encodedData[4...].toBigEndian(UInt16.self)) / 10.0
        let timerCounter = encodedData[6...].toBigEndian(UInt32.self)
        delayUntilNextTenthOfPulse = TimeInterval(hundredthsOfMilliseconds: Double(timerCounter))
        var entries = [RateEntry]()
        for entryIndex in (0..<numEntries) {
            let offset = 10 + entryIndex * 6
            let totalPulses = Double(encodedData[offset...].toBigEndian(UInt16.self)) / 10.0
            let timerCounter = encodedData[(offset+2)...].toBigEndian(UInt32.self) & ~nearZeroBasalRateFlag
            let delayBetweenPulses = TimeInterval(hundredthsOfMilliseconds: Double(timerCounter))
            entries.append(RateEntry(totalPulses: totalPulses, delayBetweenPulses: delayBetweenPulses))
        }
        rateEntries = entries
    }

    public init(currentEntryIndex: UInt8, remainingPulses: Double, delayUntilNextTenthOfPulse: TimeInterval, rateEntries: [RateEntry], acknowledgementBeep: Bool = false, completionBeep: Bool = false, programReminderInterval: TimeInterval = 0) {
        self.currentEntryIndex = currentEntryIndex
        self.remainingPulses = remainingPulses
        self.delayUntilNextTenthOfPulse = delayUntilNextTenthOfPulse
        self.rateEntries = rateEntries
        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval
    }

    public init(schedule: BasalSchedule, scheduleOffset: TimeInterval, acknowledgementBeep: Bool = false, completionBeep: Bool = false, programReminderInterval: TimeInterval = 0) {
        var rateEntries = [RateEntry]()

        let mergedSchedule = BasalSchedule(entries: schedule.entries.adjacentEqualRatesMerged())
        for entry in mergedSchedule.durations() {
            rateEntries.append(contentsOf: RateEntry.makeEntries(rate: entry.rate, duration: entry.duration))
        }

        self.rateEntries = rateEntries
        let scheduleOffsetNearestSecond = round(scheduleOffset)

        self.acknowledgementBeep = acknowledgementBeep
        self.completionBeep = completionBeep
        self.programReminderInterval = programReminderInterval

        var t: TimeInterval = 0
        var entryIndex: UInt8 = 0
        for rateEntry in rateEntries {
            let rateEntryDuration = rateEntry.duration
            if scheduleOffsetNearestSecond >= t && scheduleOffsetNearestSecond <= t + rateEntryDuration {
                self.currentEntryIndex = entryIndex

                let timeRemaining = (t + rateEntryDuration) - scheduleOffsetNearestSecond
                self.delayUntilNextTenthOfPulse = timeRemaining.truncatingRemainder(dividingBy: (rateEntry.delayBetweenPulses / 10))

                let pulsesRemaining = rateEntry.totalPulses * (timeRemaining / rateEntryDuration)
                self.remainingPulses = pulsesRemaining == 0 ? 0.1 : ceil(pulsesRemaining * 10) / 10
                return
            }
            t += rateEntryDuration
            entryIndex += 1
        }
        fatalError("RateEntry schedule incomplete")
    }
}
