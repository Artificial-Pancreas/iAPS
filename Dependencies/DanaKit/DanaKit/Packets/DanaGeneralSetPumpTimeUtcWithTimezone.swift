//
//  DanaGeneralSetPumpTimeUtcWithTimezone.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralSetPumpTimeUtcWithTimezone {
    var time: Date
    var zoneOffset: UInt8
}

let CommandGeneralSetPumpTimeUtcWithTimezone: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_OPTION__SET_PUMP_UTC_AND_TIME_ZONE & 0xff)

func generatePacketGeneralSetPumpTimeUtcWithTimezone(options: PacketGeneralSetPumpTimeUtcWithTimezone) -> DanaGeneratePacket {
    var data = Data(count: 7)
    data.addDate(at: 0, date: options.time)
    data[6] = (options.zoneOffset < 0 ? 0b10000000 : 0x0) | (options.zoneOffset & 0x7f)

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_OPTION__SET_PUMP_UTC_AND_TIME_ZONE,
        data: data
    )
}

func parsePacketGeneralSetPumpTimeUtcWithTimezone(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
