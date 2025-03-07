//
//  DanaBolusSetExtended.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBolusSetExtended {
    var extendedAmount: UInt16
    var extendedDurationInHalfHours: UInt8
}

let CommandBolusSetExtended: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BOLUS__SET_EXTENDED_BOLUS & 0xff)

func generatePacketBolusSetExtended(options: PacketBolusSetExtended) -> DanaGeneratePacket {
    var data = Data(count: 3)
    data[0] = UInt8(options.extendedAmount & 0xff)
    data[1] = UInt8((options.extendedAmount >> 8) & 0xff)
    data[2] = options.extendedDurationInHalfHours

    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__SET_EXTENDED_BOLUS, data: data)
}

func parsePacketBolusSetExtended(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: nil)
}
