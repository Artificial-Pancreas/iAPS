//
//  DanaBasalGetRate.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBasalGetRate {
    let maxBasal: Double
    let basalStep: Double
    let basalProfile: [Double]
}

let CommandBasalGetRate: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BASAL__GET_BASAL_RATE & 0xff)

func generatePacketBasalGetRate() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BASAL__GET_BASAL_RATE, data: nil)
}

func parsePacketBasalGetRate(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketBasalGetRate> {
    let maxBasal = Double(data.uint16(at: DataStart)) / 100.0
    let basalStep = Double(data[DataStart + 2]) / 100.0

    var basalProfile: [Double] = []
    for i in 0..<24 {
        let index = DataStart + 3 + i * 2
        let basalValue = Double(data.uint16(at: index)) / 100.0
        basalProfile.append(basalValue)
    }

    return DanaParsePacket(success: basalStep < 1, rawData: data, data: PacketBasalGetRate(maxBasal: maxBasal, basalStep: basalStep, basalProfile: basalProfile))
}
