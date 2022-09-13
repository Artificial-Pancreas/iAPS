//
//  BasalDeliveryTable.swift
//  OmniBLE
//
//  From OmniKit/Model/BasalDeliveryTable.swift
//  Created by Pete Schwamb on 4/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

// Max time between pulses for scheduled basal and temp basal extra timing command
let maxTimeBetweenPulses = TimeInterval(hours: 5)

// Near zero basal rate used for non-Eros pods for zero scheduled basal rates and temp basals
let nearZeroBasalRate = 0.01

// Special flag used for non-Eros pods for near zero basal rates pulse timing for $13 & $16 extra commands
let nearZeroBasalRateFlag: UInt32 = 0x80000000


public struct BasalTableEntry {
    let segments: Int
    let pulses: Int
    let alternateSegmentPulse: Bool
    
    public init(encodedData: Data) {
        segments = Int(encodedData[0] >> 4) + 1
        pulses = (Int(encodedData[0] & 0b11) << 8) + Int(encodedData[1])
        alternateSegmentPulse = (encodedData[0] >> 3) & 0x1 == 1
    }
    
    public init(segments: Int, pulses: Int, alternateSegmentPulse: Bool) {
        self.segments = segments
        self.pulses = pulses
        self.alternateSegmentPulse = alternateSegmentPulse
    }
    
    public var data: Data {
        let pulsesHighBits = UInt8((pulses >> 8) & 0b11)
        let pulsesLowBits = UInt8(pulses & 0xff)
        return Data([
            UInt8((segments - 1) << 4) + UInt8((alternateSegmentPulse ? 1 : 0) << 3) + pulsesHighBits,
            UInt8(pulsesLowBits)
            ])
    }
    
    public func checksum() -> UInt16 {
        let checksumPerSegment = (pulses & 0xff) + (pulses >> 8)
        return UInt16(checksumPerSegment * segments + (alternateSegmentPulse ? segments / 2 : 0))
    }
}

extension BasalTableEntry: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "BasalTableEntry(segments:\(segments), pulses:\(pulses), alternateSegmentPulse:\(alternateSegmentPulse))"
    }
}


public struct BasalDeliveryTable {
    static let segmentDuration: TimeInterval = .minutes(30)
    
    let entries: [BasalTableEntry]
    
    public init(entries: [BasalTableEntry]) {
        self.entries = entries
    }
    
    
    public init(schedule: BasalSchedule) {
        
        struct TempSegment {
            let pulses: Int
        }
        
        let numSegments = 48
        let maxSegmentsPerEntry = 16
        
        var halfPulseRemainder = false
        
        let expandedSegments = stride(from: 0, to: numSegments, by: 1).map { (index) -> TempSegment in
            let rate = schedule.rateAt(offset: Double(index) * .minutes(30))
            let pulsesPerHour = Int(round(rate / Pod.pulseSize))
            let pulsesPerSegment = pulsesPerHour >> 1
            let halfPulse = pulsesPerHour & 0b1 != 0
            
            let segment = TempSegment(pulses: pulsesPerSegment + ((halfPulseRemainder && halfPulse) ? 1 : 0))
            halfPulseRemainder = halfPulseRemainder != halfPulse

            return segment
        }
        
        var tableEntries = [BasalTableEntry]()

        let addEntry = { (segments: [TempSegment], alternateSegmentPulse: Bool) in
            tableEntries.append(BasalTableEntry(
                segments: segments.count,
                pulses: segments.first!.pulses,
                alternateSegmentPulse: alternateSegmentPulse
            ))
        }

        var altSegmentPulse = false
        var segmentsToMerge = [TempSegment]()
        
        for segment in expandedSegments {
            guard let firstSegment = segmentsToMerge.first else {
                segmentsToMerge.append(segment)
                continue
            }
            
            let delta = segment.pulses - firstSegment.pulses
            
            if segmentsToMerge.count == 1 {
                altSegmentPulse = delta == 1
            }
            
            let expectedDelta: Int
            
            if !altSegmentPulse {
                expectedDelta = 0
            } else {
                expectedDelta = segmentsToMerge.count % 2
            }
            
            if expectedDelta != delta || segmentsToMerge.count == maxSegmentsPerEntry {
                addEntry(segmentsToMerge, altSegmentPulse)
                segmentsToMerge.removeAll()
            }
            
            segmentsToMerge.append(segment)
        }
        addEntry(segmentsToMerge, altSegmentPulse)

        self.entries = tableEntries
    }
    
    public init(tempBasalRate: Double, duration: TimeInterval) {
        self.entries = BasalDeliveryTable.rateToTableEntries(rate: tempBasalRate, duration: duration)
    }
    
    private static func rateToTableEntries(rate: Double, duration: TimeInterval) -> [BasalTableEntry] {
        var tableEntries = [BasalTableEntry]()
        
        let pulsesPerHour = Int(round(rate / Pod.pulseSize))
        let pulsesPerSegment = pulsesPerHour >> 1
        let alternateSegmentPulse = pulsesPerHour & 0b1 != 0
        
        var remaining = Int(round(duration / BasalDeliveryTable.segmentDuration))
        
        while remaining > 0 {
            let segments = min(remaining, 16)
            let tableEntry = BasalTableEntry(segments: segments, pulses: Int(pulsesPerSegment), alternateSegmentPulse: segments > 1 ? alternateSegmentPulse : false)
            tableEntries.append(tableEntry)
            remaining -= segments
        }
        return tableEntries
    }
    
    public func numSegments() -> Int {
        return entries.reduce(0) { $0 + $1.segments }
    }
}

extension BasalDeliveryTable: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "BasalDeliveryTable(\(entries))"
    }
}

// Round basal rate by rounding down to pulse size boundary,
// but basal rates within a small delta will be rounded up.
// Rounds down to 0 for both non-Eros and Eros (temp basals).
func roundToSupportedBasalRate(rate: Double) -> Double
{
    let delta = 0.01
    let supportedBasalRates: [Double] = (0...600).map { Double($0) / Double(Pod.pulsesPerUnit) }
    return supportedBasalRates.last(where: { $0 <= rate + delta }) ?? 0
}

// Return rounded basal rate for pulse timing purposes.
// For non-Eros, returns nearZeroBasalRate (0.01) for a zero basal rate.
func roundToSupportedBasalTimingRate(rate: Double) -> Double {
    var rrate = roundToSupportedBasalRate(rate: rate)
    if rrate == 0.0 {
        rrate = Pod.zeroBasalRate // will be an adjusted value for non-Eros cases
    }
    return rrate
}

public struct RateEntry {
    let totalPulses: Double
    let delayBetweenPulses: TimeInterval
    
    public init(totalPulses: Double, delayBetweenPulses: TimeInterval) {
        self.totalPulses = totalPulses
        self.delayBetweenPulses = delayBetweenPulses
    }
    
    public var rate: Double {
        if totalPulses == 0 {
            // Eros zero TB is the only case not using pulses
            return 0
        } else {
            // Use delayBetweenPulses to compute rate, works for non-Eros near zero rates
            return (.hours(1) / delayBetweenPulses) / Pod.pulsesPerUnit
        }
    }
    
    public var duration: TimeInterval {
        if totalPulses == 0 {
            // Eros zero TB case uses fixed 30 minute rate entries
            return TimeInterval(minutes: 30)
        } else {
            // Use delayBetweenPulses to compute duration, works for non-Eros near zero rates
            return delayBetweenPulses * totalPulses
        }
    }
    
    public var data: Data {
        var delayBetweenPulsesInHundredthsOfMillisecondsWithFlag = UInt32(delayBetweenPulses.hundredthsOfMilliseconds)

        // non-Eros near zero basal rates use the nearZeroBasalRateFlag
        if delayBetweenPulses == maxTimeBetweenPulses && totalPulses != 0 {
            delayBetweenPulsesInHundredthsOfMillisecondsWithFlag |= nearZeroBasalRateFlag
        }

        var data = Data()
        data.appendBigEndian(UInt16(round(totalPulses * 10)))
        data.appendBigEndian(delayBetweenPulsesInHundredthsOfMillisecondsWithFlag)
        return data
    }
    
    public static func makeEntries(rate: Double, duration: TimeInterval) -> [RateEntry] {
        let maxPulsesPerEntry: Double = 6400 // PDM's cutoff on # of 1/10th pulses encoded in 2-byte value
        var entries = [RateEntry]()
        let rrate = roundToSupportedBasalTimingRate(rate: rate)
        
        var remainingSegments = Int(round(duration.minutes / 30))
        
        let pulsesPerSegment = round(rrate / Pod.pulseSize) / 2
        let maxSegmentsPerEntry = pulsesPerSegment > 0 ? Int(maxPulsesPerEntry / pulsesPerSegment) : 1
        
        var remainingPulses = rrate * duration.hours / Pod.pulseSize

        while (remainingSegments > 0) {
            let entry: RateEntry
            if rrate == 0 {
                // Eros zero TBR only, one rate entry per segment with no pulses
                entry = RateEntry(totalPulses: 0, delayBetweenPulses: maxTimeBetweenPulses)
                remainingSegments -= 1 // one rate entry per half hour
            } else if rrate == nearZeroBasalRate {
                // Non-Eros near zero value temp or scheduled basal, one entry with 1/10 pulse per 1/2 hour of duration
                entry = RateEntry(totalPulses: Double(remainingSegments) / 10, delayBetweenPulses: maxTimeBetweenPulses)
                remainingSegments = 0 // just a single entry
            } else {
                let numSegments = min(maxSegmentsPerEntry, Int(round(remainingPulses / pulsesPerSegment)))
                remainingSegments -= numSegments
                let pulseCount = pulsesPerSegment * Double(numSegments)
                let delayBetweenPulses = .hours(1) / rrate * Pod.pulseSize
                entry = RateEntry(totalPulses: pulseCount, delayBetweenPulses: delayBetweenPulses)
                remainingPulses -= pulseCount
            }
            entries.append(entry)
        }
        return entries
    }
}

extension RateEntry: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "RateEntry(rate:\(rate) duration:\(duration.stringValue))"
    }
}
