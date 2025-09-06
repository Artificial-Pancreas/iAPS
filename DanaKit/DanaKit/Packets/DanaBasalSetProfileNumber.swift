//
//  DanaBasalSetProfileNumber.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBasalSetProfileNumber {
    let profileNumber: UInt8
}

let CommandBasalSetProfileNumber: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__SET_PROFILE_NUMBER & 0xff)
func generatePacketBasalSetProfileNumber(options: PacketBasalSetProfileNumber) -> DanaGeneratePacket {
    let data = Data([options.profileNumber & 0xff])

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_PROFILE_NUMBER, data: data)
}

func parsePacketBasalSetProfileNumber(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
