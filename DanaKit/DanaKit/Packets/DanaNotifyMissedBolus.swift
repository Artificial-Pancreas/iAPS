//
//  DanaNotifyMissedBolus.swift
//  
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//

struct PacketNotifyMissedBolus {
    var startTime: Date
    var endTime: Date
}

let CommandNotifyMissedBolus: UInt16 = (UInt16(DanaPacketType.TYPE_NOTIFY & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_NOTIFY__MISSED_BOLUS_ALARM & 0xff)

func parsePacketNotifyMissedBolus(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketNotifyMissedBolus> {
    let startTime = Date(
        timeIntervalSinceReferenceDate: TimeInterval(
            (UInt16(data[DataStart]) * 3600 + UInt16(data[DataStart + 1]) * 60) * 60
        )
    )

    let endTime = Date(
        timeIntervalSinceReferenceDate: TimeInterval(
            (UInt16(data[DataStart + 2]) * 3600 + UInt16(data[DataStart + 3]) * 60) * 60
        )
    )

    return DanaParsePacket(
        success: data[DataStart] != 0x01 && data[DataStart + 1] != 0x01 && data[DataStart + 2] != 0x01 && data[DataStart + 3] != 0x01,
        notifyType: CommandNotifyMissedBolus,
        rawData: data,
        data: PacketNotifyMissedBolus(
            startTime: startTime,
            endTime: endTime
        )
    )
}
