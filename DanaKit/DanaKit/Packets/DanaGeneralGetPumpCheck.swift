//
//  DanaGeneralGetPumpCheck.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralGetPumpCheck {
    let hwModel: UInt8
    let protocolCode: UInt8
    let productCode: UInt8
}

let CommandGeneralGetPumpCheck: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__GET_PUMP_CHECK & 0xff)

func generatePacketGeneralGetPumpCheck() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_REVIEW__GET_PUMP_CHECK, data: nil)
}

func parsePacketGeneralGetPumpCheck(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketGeneralGetPumpCheck> {
    return DanaParsePacket(
        success: data[4] < 4, // Unsupported hardware...
        rawData: data,
        data: PacketGeneralGetPumpCheck(
            hwModel: data[DataStart],
            protocolCode: data[DataStart + 1],
            productCode: data[DataStart + 2]
        )
    )
}
