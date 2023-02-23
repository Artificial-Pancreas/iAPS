//
//  G7BackfillMessage.swift
//  CGMBLEKit
//
//  Created by Pete Schwamb on 9/25/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

public struct G7BackfillMessage: Equatable {

    public let timestamp: UInt32 // Seconds since pairing
    public let glucose: UInt16?
    public let glucoseIsDisplayOnly: Bool
    public let algorithmState: AlgorithmState
    public let trend: Double?

    public let data: Data

    public var hasReliableGlucose: Bool {
        return algorithmState.hasReliableGlucose
    }

    init?(data: Data) {
        //    0 1 2  3  4 5  6  7  8
        //   TTTTTT    BGBG SS    TR
        //   45a100 00 9600 06 0f fc

        guard data.count == 9 else {
            return nil
        }

        timestamp = data[0..<4].toInt()

        let glucoseBytes = data[4..<6].to(UInt16.self)

        if glucoseBytes != 0xffff {
            glucose = glucoseBytes & 0xfff
            glucoseIsDisplayOnly = (glucoseBytes & 0xf000) > 0
        } else {
            glucose = nil
            glucoseIsDisplayOnly = false
        }

        algorithmState = AlgorithmState(rawValue: data[6])

        if data[8] == 0x7f {
            trend = nil
        } else {
            trend = Double(Int8(bitPattern: data[8])) / 10
        }

        self.data = data
    }

    public var trendType: LoopKit.GlucoseTrend? {
        guard let trend = trend else {
            return nil
        }

        switch trend {
        case let x where x <= -3.0:
            return .downDownDown
        case let x where x <= -2.0:
            return .downDown
        case let x where x <= -1.0:
            return .down
        case let x where x < 1.0:
            return .flat
        case let x where x < 2.0:
            return .up
        case let x where x < 3.0:
            return .upUp
        default:
            return .upUpUp
        }
    }

    public var condition: GlucoseCondition? {
        guard let glucose = glucose else {
            return nil
        }

        if glucose < GlucoseLimits.minimum {
            return .belowRange
        } else if glucose > GlucoseLimits.maximum {
            return .aboveRange
        } else {
            return nil
        }
    }
}

extension G7BackfillMessage: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "G7BackfillMessage(glucose:\(String(describing: glucose)), glucoseIsDisplayOnly:\(glucoseIsDisplayOnly) timestamp:\(timestamp), data:\(data.hexadecimalString))"
    }
}
