//
//  DanaBolusGetStepInformation.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBolusGetStepInformation {
    var bolusType: UInt8
    var initialBolusAmount: Double
    var lastBolusTime: Date
    var lastBolusAmount: Double
    var maxBolus: Double
    var bolusStep: UInt8
}

let CommandBolusGetStepInformation: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BOLUS__GET_STEP_BOLUS_INFORMATION & 0xff)

func generatePacketBolusGetStepInformation() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__GET_STEP_BOLUS_INFORMATION, data: nil)
}

func parsePacketBolusGetStepInformation(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketBolusGetStepInformation> {
    let lastBolusTime = Calendar.current.date(bySettingHour: Int(data[DataStart + 4]), minute: Int(data[DataStart + 5]), second: 0, of: Date()) ?? Date()

    return DanaParsePacket(success: data[DataStart] == 0, rawData: data, data: PacketBolusGetStepInformation(
        bolusType: data[DataStart + 1],
        initialBolusAmount: Double(data.uint16(at: DataStart + 2)) / 100,
        lastBolusTime: lastBolusTime,
        lastBolusAmount: Double(data.uint16(at: DataStart + 6)) / 100,
        maxBolus: Double(data.uint16(at: DataStart + 8)) / 100,
        bolusStep: data[DataStart + 10]
    ))
}
