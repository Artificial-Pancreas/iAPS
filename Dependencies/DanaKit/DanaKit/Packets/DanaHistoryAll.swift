//
//  DanaHistoryAll.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandHistoryAll: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__ALL_HISTORY & 0xff)

func generatePacketHistoryAll(options: PacketHistoryBase) -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__ALL_HISTORY,
        data: generatePacketHistoryData(options: options)
    )
}
