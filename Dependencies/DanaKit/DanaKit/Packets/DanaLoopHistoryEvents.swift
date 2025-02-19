//
//  DanaLoopHistoryEvents.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketLoopHistoryEvents {
    var from: Date?
}

let CommandLoopHistoryEvents: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE__APS_HISTORY_EVENTS & 0xff)

func generatePacketLoopHistoryEvents(options: PacketLoopHistoryEvents) -> DanaGeneratePacket {
    var data = Data(count: 6)

    if options.from == nil {
        data[0] = 0
        data[1] = 1
        data[2] = 1
        data[3] = 0
        data[4] = 0
        data[5] = 0
    } else {
        data.addDate(at: 0, date: options.from!)
    }

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE__APS_HISTORY_EVENTS,
        data: data
    )
}

func parsePacketLoopHistoryEvents(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    // Implement the parse logic as needed
    fatalError("Not implemented")
}
