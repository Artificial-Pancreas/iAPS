//
//  DanaNotifyAlarm.swift
//  
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//

struct PacketNotifyAlarm {
    var code: UInt8
    var message: String
}

let CommandNotifyAlarm: UInt16 = (UInt16(DanaPacketType.TYPE_NOTIFY & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_NOTIFY__ALARM & 0xff)

func parsePacketNotifyAlarm(data: Data) -> DanaParsePacket<PacketNotifyAlarm> {
    let code = data[DataStart]
    let message = DANA_NOTIFY_ALARM[Int(code)] ?? ""

    return DanaParsePacket(
        success: true,
        notifyType: CommandNotifyAlarm,
        data: PacketNotifyAlarm(
            code: code,
            message: message
        )
    )
}

let DANA_NOTIFY_ALARM: [Int: String] = [
    0x01: "Battery 0%",
    0x02: "Pump error",
    0x03: "Occlusion",
    0x04: "Low battery",
    0x05: "Shutdown",
    0x06: "Basal compare",
    0x07: "Blood sugar measurement alert",
    0xff: "Blood sugar measurement alert",
    0x08: "Remaining insulin level",
    0xfe: "Remaining insulin level",
    0x09: "Empty reservoir",
    0x0a: "Check shaft",
    0x0b: "Basal MAX",
    0x0c: "Daily MAX",
    0xfd: "Blood sugar check miss alarm",
]

