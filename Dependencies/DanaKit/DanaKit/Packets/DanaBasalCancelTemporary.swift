//
//  DanaPacketBasalCancelTemporary.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandBasalCancelTemporary: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__CANCEL_TEMPORARY_BASAL & 0xff)

func generatePacketBasalCancelTemporary() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__CANCEL_TEMPORARY_BASAL, data: nil)
}

func parsePacketBasalCancelTemporary(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
