//
//  GlucoseRxMessage.swift
//  xDrip5
//
//  Created by Nathan Racklyeft on 11/23/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation


public struct GlucoseSubMessage: TransmitterRxMessage {
    static let size = 8

    public let timestamp: UInt32
    public let glucoseIsDisplayOnly: Bool
    public let glucose: UInt16
    public let state: UInt8
    public let trend: Int8

    init?(data: Data) {
        guard data.count >= GlucoseSubMessage.size else {
            return nil
        }

        var start = data.startIndex
        var end = start.advanced(by: 4)
        timestamp = data[start..<end].toInt()

        start = end
        end = start.advanced(by: 2)
        let glucoseBytes = data[start..<end].to(UInt16.self)
        glucoseIsDisplayOnly = (glucoseBytes & 0xf000) > 0
        glucose = glucoseBytes & 0xfff

        start = end
        end = start.advanced(by: 1)
        state = data[start]

        start = end
        end = start.advanced(by: 1)
        trend = Int8(bitPattern: data[start])
    }
}


public struct GlucoseRxMessage: TransmitterRxMessage {
    public let status: UInt8
    public let sequence: UInt32
    public let glucose: GlucoseSubMessage

    init?(data: Data) {
        guard data.count >= 16 && data.isCRCValid else {
            return nil
        }

        guard data.starts(with: .glucoseRx) || data.starts(with: .glucoseG6Rx) else {
            return nil
        }

        status = data[1]
        sequence = data[2..<6].toInt()

        guard let glucose = GlucoseSubMessage(data: data[6...]) else {
            return nil
        }
        self.glucose = glucose
    }
}

extension GlucoseSubMessage: Equatable {
    public static func ==(lhs: GlucoseSubMessage, rhs: GlucoseSubMessage) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
            lhs.glucoseIsDisplayOnly == rhs.glucoseIsDisplayOnly &&
            lhs.glucose == rhs.glucose &&
            lhs.state == rhs.state &&
            lhs.trend == rhs.trend
    }
}


extension GlucoseRxMessage: Equatable {
    public static func ==(lhs: GlucoseRxMessage, rhs: GlucoseRxMessage) -> Bool {
        return lhs.status == rhs.status &&
            lhs.sequence == rhs.sequence &&
            lhs.glucose == rhs.glucose
    }
}
