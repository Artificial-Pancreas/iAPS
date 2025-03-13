//
//  DanaBasalSetSuspendOff.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandBasalSetSuspendOff: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__SET_SUSPEND_OFF & 0xff)

func generatePacketBasalSetSuspendOff() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_SUSPEND_OFF, data: nil)
}

func parsePacketBasalSetSuspendOff(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
