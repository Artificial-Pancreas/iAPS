//
//  DanaGeneralClearUserTimeChangeFlag.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandGeneralClearUserTimeChangeFlag: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__SET_USER_TIME_CHANGE_FLAG_CLEAR & 0xff)

func generatePacketGeneralClearUserTimeChangeFlag() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_REVIEW__SET_USER_TIME_CHANGE_FLAG_CLEAR, data: nil)
}

func parsePacketGeneralClearUserTimeChangeFlag(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
