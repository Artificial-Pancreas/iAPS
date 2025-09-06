//
//  DanaNotifyAlarm.swift
//  
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//

struct PacketNotifyAlarm {
    var code: UInt8
    var alert: PumpManagerAlert
}

let CommandNotifyAlarm: UInt16 = (UInt16(DanaPacketType.TYPE_NOTIFY & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_NOTIFY__ALARM & 0xff)

func parsePacketNotifyAlarm(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketNotifyAlarm> {
    let DANA_NOTIFY_ALARM: [Int: PumpManagerAlert] = [
        0x01: PumpManagerAlert.batteryZeroPercent(data),
        0x02: PumpManagerAlert.pumpError(data),
        0x03: PumpManagerAlert.occlusion(data),
        0x04: PumpManagerAlert.lowBattery(data),
        0x05: PumpManagerAlert.shutdown(data),
        0x06: PumpManagerAlert.basalCompare(data),
        0x07: PumpManagerAlert.bloodSugarMeasure(data),
        0xff: PumpManagerAlert.bloodSugarMeasure(data),
        0x08: PumpManagerAlert.remainingInsulinLevel(data),
        0xfe: PumpManagerAlert.remainingInsulinLevel(data),
        0x09: PumpManagerAlert.emptyReservoir(data),
        0x0a: PumpManagerAlert.checkShaft(data),
        0x0b: PumpManagerAlert.basalMax(data),
        0x0c: PumpManagerAlert.dailyMax(data),
        0xfd: PumpManagerAlert.bloodSugarCheckMiss(data),
    ]
    
    let code = data[DataStart]
    let alert = DANA_NOTIFY_ALARM[Int(code)] ?? PumpManagerAlert.unknown(nil)

    return DanaParsePacket(
        success: true,
        notifyType: CommandNotifyAlarm,
        rawData: data,
        data: PacketNotifyAlarm(
            code: code,
            alert: alert
        )
    )
}
