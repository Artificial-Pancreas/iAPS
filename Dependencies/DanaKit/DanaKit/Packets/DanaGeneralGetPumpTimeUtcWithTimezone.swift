//
//  DanaGeneralGetPumpTimeUtcWithTimezone.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralGetPumpTimeUtcWithTimezone {
    var time: Date
}

let CommandGeneralGetPumpTimeUtcWithTimezone: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_OPTION__GET_PUMP_UTC_AND_TIME_ZONE & 0xff)

func generatePacketGeneralGetPumpTimeUtcWithTimezone() -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_OPTION__GET_PUMP_UTC_AND_TIME_ZONE,
        data: nil
    )
}

func parsePacketGeneralGetPumpTimeUtcWithTimezone(data: Data) -> DanaParsePacket<PacketGeneralGetPumpTimeUtcWithTimezone> {
    let timezoneData = data[DataStart + 6]
    let timezoneOffset = Int(Int8(timezoneData))

    // Convert from UTC
    let time = DateComponents(
        calendar: .current,
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2000 + Int(data[DataStart]),
        month: Int(data[DataStart + 1]),
        day: Int(data[DataStart + 2]),
        hour: Int(data[DataStart + 3]) + timezoneOffset,
        minute: Int(data[DataStart + 4]),
        second: Int(data[DataStart + 5])
    )

    guard let parsedTime = Calendar.current.date(from: time) else {
        // Handle error, if needed
        return DanaParsePacket(success: false, data: nil)
    }

    return DanaParsePacket(
        success: true,
        data: PacketGeneralGetPumpTimeUtcWithTimezone(time: parsedTime)
    )
}
