//
//  DanaGeneralGetPumpDecRatio.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralGetPumpDecRatio {
    var decRatio: UInt8
}

let CommandGeneralGetPumpDecRatio: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__GET_PUMP_DEC_RATIO & 0xff)

func generatePacketGeneralGetPumpDecRatio() -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__GET_PUMP_DEC_RATIO,
        data: nil
    )
}

func parsePacketGeneralGetPumpDecRatio(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketGeneralGetPumpDecRatio> {
    return DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetPumpDecRatio(
            decRatio: data[DataStart] * 5
        )
    )
}
