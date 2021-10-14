//
//  GlucoseBackfillMessage.swift
//  xDripG5
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

// 50 05 02 00 b7ff5200 66045300 00000000 0000 7138

struct GlucoseBackfillTxMessage: RespondableMessage {
    typealias Response = GlucoseBackfillRxMessage

    let byte1: UInt8
    let byte2: UInt8
    let identifier: UInt8

    let startTime: UInt32
    let endTime: UInt32

    let length: UInt32 = 0
    let backfillCRC: UInt16 = 0

    var data: Data {
        var data = Data(for: .glucoseBackfillTx)
        data.append(contentsOf: [byte1, byte2, identifier])
        data.append(startTime)
        data.append(endTime)
        data.append(length)
        data.append(backfillCRC)

        return data.appendingCRC()
    }
}

// 51 00 01 00 b7ff5200 66045300 32000000 e6cb 9805

struct GlucoseBackfillRxMessage: TransmitterRxMessage {
    let status: UInt8
    let backfillStatus: UInt8
    let identifier: UInt8
    let startTime: UInt32
    let endTime: UInt32
    let bufferLength: UInt32
    let bufferCRC: UInt16

    init?(data: Data) {
        guard data.count == 20,
            data.isCRCValid,
            data.starts(with: .glucoseBackfillRx)
        else {
            return nil
        }

        status = data[1]
        backfillStatus = data[2]
        identifier = data[3]
        startTime = data[4..<8].toInt()
        endTime = data[8..<12].toInt()
        bufferLength = data[12..<16].toInt()
        bufferCRC = data[16..<18].toInt()
    }
}

// 0100bc460000b7ff52008b0006eee30053008500
// 020006eb0f025300800006ee3a0353007e0006f5
// 030066045300790006f8

struct GlucoseBackfillFrameBuffer {
    let identifier: UInt8
    private var frames: [Data] = []

    init(identifier: UInt8) {
        self.identifier = identifier
    }

    mutating func append(_ frame: Data) {
        // Byte 0 is the frame index
        // Byte 1 is the identifier
        guard frame.count > 2,
            frame[0] == frames.count + 1,
            frame[1] == identifier else {
            return
        }

        frames.append(frame)
    }

    var count: Int {
        return frames.reduce(0, { $0 + $1.count })
    }

    var crc16: UInt16 {
        return frames.reduce(into: Data(), { $0.append($1) }).crc16
    }

    var glucose: [GlucoseSubMessage] {
        // Drop the first 2 bytes from each frame
        let data = frames.reduce(into: Data(), { $0.append($1.dropFirst(2)) })

        // Drop the first 4 bytes from the combined message
        // Byte 0: ??
        // Byte 1: ??
        // Byte 2: ?? (only seen 0 so far)
        // Byte 3: ?? (only seen 0 so far)
        let glucoseData = data.dropFirst(4)

        return stride(
            from: glucoseData.startIndex,
            to: glucoseData.endIndex,
            by: GlucoseSubMessage.size
        ).compactMap {
            let range = $0..<$0.advanced(by: GlucoseSubMessage.size)
            guard glucoseData.endIndex >= range.endIndex else {
                return nil
            }

            return GlucoseSubMessage(data: glucoseData[range])
        }
    }
}
