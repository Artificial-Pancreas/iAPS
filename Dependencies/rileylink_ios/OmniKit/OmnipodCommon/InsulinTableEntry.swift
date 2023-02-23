//
//  InsulinTableEntry.swift
//  OmniKit
//
//  Created by Joseph Moran on 10/26/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

//
// InsulinTableEntry describes the common InsulinScheduleElement in all the 0x1A insulin delivery commands.
// See https://github.com/openaps/openomni/wiki/Command-1A-Insulin-Schedule#InsulinScheduleElement for details.
// Formerly BasalTableEntry when only being used for the basal and temporary basal commands.
//
public struct InsulinTableEntry {
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

extension InsulinTableEntry: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "InsulinTableEntry(segments:\(segments), pulses:\(pulses), alternateSegmentPulse:\(alternateSegmentPulse))"
    }
}
