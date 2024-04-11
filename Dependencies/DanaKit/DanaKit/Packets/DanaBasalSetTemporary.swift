//
//  DanaBasalSetTemporary.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBasalSetTemporary {
    /// Ratio is in percentage
    var temporaryBasalRatio: UInt8
    
    /// Only whole hours are accepted
    var temporaryBasalDuration: UInt8
}

let CommandBasalSetTemporary: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__SET_TEMPORARY_BASAL & 0xff)

func generatePacketBasalSetTemporary(options: PacketBasalSetTemporary) -> DanaGeneratePacket {
    let data = Data([options.temporaryBasalRatio, options.temporaryBasalDuration])

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__SET_TEMPORARY_BASAL, data: data)
}

func parsePacketBasalSetTemporary(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
