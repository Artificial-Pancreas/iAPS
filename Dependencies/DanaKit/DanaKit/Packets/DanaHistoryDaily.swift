//
//  DanaHistoryDaily.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandHistoryDaily: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__DAILY & 0xff)

func generatePacketHistoryDaily(options: PacketHistoryBase) -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__DAILY,
        data: generatePacketHistoryData(options: options)
    )
}
