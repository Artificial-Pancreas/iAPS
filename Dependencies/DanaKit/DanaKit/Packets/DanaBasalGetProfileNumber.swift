//
//  DanaPacketBasalGetProfileNumber.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBasalGetProfileNumber {
    let activeProfile: UInt8
}

let CommandBasalGetProfileNumber: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__GET_PROFILE_BASAL_RATE & 0xff)

func generatePacketBasalGetProfileNumber() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__GET_PROFILE_BASAL_RATE, data: nil)
}

func parsePacketBasalGetProfileNumber(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketBasalGetProfileNumber> {
    return DanaParsePacket(success: true, rawData: data, data: PacketBasalGetProfileNumber(activeProfile: data[DataStart]))
}
