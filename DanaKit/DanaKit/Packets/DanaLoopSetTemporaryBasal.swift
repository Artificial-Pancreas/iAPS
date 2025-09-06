//
//  DanaLoopSetTemporaryBasal.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

enum LoopTempBasalDuration {
    case min15
    case min30
}

struct PacketLoopSetTemporaryBasal {
    var percent: UInt16
    var duration: LoopTempBasalDuration
}

struct TemporaryBasalDuration {
    static let PARAM_30_MIN: UInt8 = 160
    static let PARAM_15_MIN: UInt8 = 150
}

let CommandLoopSetTemporaryBasal: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__APS_SET_TEMPORARY_BASAL & 0xff)

func generatePacketLoopSetTemporaryBasal(options: PacketLoopSetTemporaryBasal) -> DanaGeneratePacket {
    var percent = options.percent

    if percent > 500 {
        percent = 500
    }

    let data = Data([
        UInt8(percent & 0xff),
        UInt8((percent >> 8) & 0xff),
        UInt8((options.duration == .min30 ? TemporaryBasalDuration.PARAM_30_MIN : TemporaryBasalDuration.PARAM_15_MIN) & 0xff),
    ])

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_BASAL__APS_SET_TEMPORARY_BASAL,
        data: data
    )
}

func parsePacketLoopSetTemporaryBasal(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
