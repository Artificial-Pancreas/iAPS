//
//  DanaGeneralGetUserTimeChangeFlag.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralGetUserTimeChangeFlag {
    var userTimeChangeFlag: UInt8
}

let CommandGeneralGetUserTimeChangeFlag: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__GET_USER_TIME_CHANGE_FLAG & 0xff)

func generatePacketGeneralGetUserTimeChangeFlag() -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__GET_USER_TIME_CHANGE_FLAG,
        data: nil
    )
}

func parsePacketGeneralGetUserTimeChangeFlag(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketGeneralGetUserTimeChangeFlag> {
    guard data.count >= 3 else {
        return DanaParsePacket(
            success: false,
            rawData: data,
            data: PacketGeneralGetUserTimeChangeFlag(userTimeChangeFlag: 0)
        )
    }

    return DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetUserTimeChangeFlag(userTimeChangeFlag: data[DataStart])
    )
}
