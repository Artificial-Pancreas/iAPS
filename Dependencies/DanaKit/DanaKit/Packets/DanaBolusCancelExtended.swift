//
//  DanaBolusCancelExtended.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandBolusCancelExtended: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BOLUS__SET_EXTENDED_BOLUS_CANCEL & 0xff)

func generatePacketBolusCancelExtended() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_EXTENDED_BOLUS_CANCEL, data: nil)
}

func parsePacketBolusCancelExtended(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
