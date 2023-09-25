//
//  BolusDeliveryTable.swift
//  OmniBLE
//
//  Created by Joseph Moran on 10/20/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

// Implements the bolus insulin delivery table for 0x1A command (https://github.com/openaps/openomni/wiki/Command-1A-Table-2)

public struct BolusDeliveryTable {
    static let segMinutes = 30
    static let maxDurationHours = 8

    let entries: [InsulinTableEntry]

    public init(entries: [InsulinTableEntry]) {
        self.entries = entries
    }

    public init(units: Double, extendedUnits: Double = 0.0, extendedDuration: TimeInterval = 0) {
        let immediatePulses = Int(round(units / Pod.pulseSize))
        let extendedPulses = Int(round(extendedUnits / Pod.pulseSize))
        let duration: TimeInterval

        let maxExtendedDuration: TimeInterval = .hours(Double(min(extendedPulses, BolusDeliveryTable.maxDurationHours)))
        if extendedDuration > maxExtendedDuration {
            // maximum extended bolus duration of one extended pulse per hour capped at 8 hours
            duration = maxExtendedDuration
        } else {
            duration = extendedDuration
        }

        self.entries = generateBolusTable(immediatePulses: immediatePulses, extendedPulses: extendedPulses, extendedDuration: duration)
    }

    public func numSegments() -> Int {
        return entries.reduce(0) { $0 + $1.segments }
    }
}

// Returns the bolus insulin delivery table for the specified bolus parameters as per the PDM.
// See https://github.com/openaps/openomni/wiki/Command-1A-Table-2#Advanced-Extended-Bolus-Encoding for details.
fileprivate func generateBolusTable(immediatePulses: Int, extendedPulses: Int, extendedDuration: TimeInterval) -> [InsulinTableEntry] {
    var tableEntries = [InsulinTableEntry]()

    if extendedPulses == 0 || extendedDuration == 0 {
        // trivial immediate bolus case ($0ppp)
        let entry = InsulinTableEntry(segments: 1, pulses: immediatePulses, alternateSegmentPulse: false)
        tableEntries.append(entry)
        return tableEntries
    }

    // Extended (square wave) bolus or combination (dual wave) bolus case
    let ePulsesPerSeg = computeExtendedPulsesPerSeg(extendedPulses: extendedPulses, duration: extendedDuration)
    let nseg = ePulsesPerSeg.count

    // The first entry is special as its pulses value always matches the # immediate pulses,
    // but it also describes the first 1/2 hour of the extended bolus when the # of extended
    // pulses in the first 1/2 hour is one more or the same as the # of immediate pulses.
    var pulses = immediatePulses
    var segs = 1
    var alternateSegmentPulse = false
    if ePulsesPerSeg[0] - 1 == immediatePulses {
        // $18ii case
        segs += 1
        alternateSegmentPulse = true
    } else if ePulsesPerSeg[0] == immediatePulses {
        // $x0ii case
        segs += 1
        if immediatePulses != 0 {
            segs += numMatch(ePulsesPerSeg: ePulsesPerSeg, idx: 0, val: immediatePulses)
        }
    } // else $00ii case describing just the immediate bolus portion -- nothing to adjust

    let entry = InsulinTableEntry(segments: segs, pulses: pulses, alternateSegmentPulse: alternateSegmentPulse)
    tableEntries.append(entry)

    var remainingPulses = (immediatePulses + extendedPulses) - (segs * pulses)
    if alternateSegmentPulse {
        remainingPulses -= segs/2
    }

    var idx: Int
    if alternateSegmentPulse {
        idx = 1
    } else {
        idx = segs - 1
    }

    // Step through the remaining extended pulses per segment array to generate and append the appropriate insulin table entries
    let basePulsesPerSeg = Int(extendedPulses / nseg) // truncated to whole pulses per half hour segment
    while idx < nseg && remainingPulses > 0 {
        segs = 1
        alternateSegmentPulse = false
        pulses = basePulsesPerSeg
        if idx < nseg - 1 && ePulsesPerSeg[idx] == pulses && ePulsesPerSeg[idx + 1] == pulses + 1 {
            // $n8bb
            let numAltPairs = numAltPairMatch(ePulsesPerSeg: ePulsesPerSeg, idx: idx, val: pulses)
            alternateSegmentPulse = true
            segs += (numAltPairs * 2) - 1
            idx += (numAltPairs * 2) - 1
            remainingPulses -= segs/2
        } else {
            // $n0bb
            pulses = ePulsesPerSeg[idx]
            let numMatched = numMatch(ePulsesPerSeg: ePulsesPerSeg, idx: idx, val: pulses)
            if numMatched > 0 {
                segs += numMatched
                idx += numMatched
            }
        }

        let entry = InsulinTableEntry(segments: segs, pulses: pulses, alternateSegmentPulse: alternateSegmentPulse)
        tableEntries.append(entry)

        idx += 1
        remainingPulses -= segs * pulses
    }

    return tableEntries
}

// Returns an array of pulses to be delivered for each half hour segment for extendedPulses spaced over the given duration
fileprivate func computeExtendedPulsesPerSeg(extendedPulses: Int, duration: TimeInterval) -> [Int] {
    let nseg = Int(ceil(duration / .minutes(BolusDeliveryTable.segMinutes)))
    let pulseInterval = duration / Double(extendedPulses)

    var ePulsesPerSeg = Array(repeating: 0, count: nseg)
    var t = pulseInterval
    var ePulses = 0
    for seg in 0..<nseg {
        let segTimeStart = TimeInterval(Double(seg) * .minutes(BolusDeliveryTable.segMinutes))
        let segTimeEnd = min(segTimeStart + .minutes(BolusDeliveryTable.segMinutes), duration)
        while t <= segTimeEnd {
            if t > segTimeStart && t <= segTimeEnd {
                ePulsesPerSeg[seg] += 1
                ePulses += 1
            }
            t += pulseInterval
        }
        if t > duration {
            break
        }
    }

    // Any remaining pulses are added to the last half hour segment
    if extendedPulses > ePulses {
        ePulsesPerSeg[nseg - 1] += extendedPulses - ePulses
    }

    return ePulsesPerSeg
}

// Returns the number of consecutive matched [val, val+1] pairs starting at ePulsesPerSeg[idx]
fileprivate func numAltPairMatch(ePulsesPerSeg: [Int], idx: Int, val: Int) -> Int {
    var cnt = 0

    for i in stride(from: idx, to: ePulsesPerSeg.count - 1, by: 2) {
        if ePulsesPerSeg[i] != val || ePulsesPerSeg[i + 1] != val + 1 {
            break
        }
        cnt += 1
    }
    return cnt
}

// Returns the number of consecutive elements matching val starting at ePulsesPerSeg[idx]
fileprivate func numMatch(ePulsesPerSeg: [Int], idx: Int, val: Int) -> Int {
    var cnt = 0

    for i in idx..<ePulsesPerSeg.count - 1 {
        if ePulsesPerSeg[i + 1] != val {
            break
        }
        cnt += 1
    }
    return cnt
}
