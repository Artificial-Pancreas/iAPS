//
//  DanaBolusGetStepInformation.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 10/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketBolusGetStepInformation {
    var bolusType: UInt8
    var initialBolusAmount: Float
    var lastBolusTime: Date
    var lastBolusAmount: Float
    var maxBolus: Float
    var bolusStep: UInt8
}

let CommandBolusGetStepInformation: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_BOLUS__GET_STEP_BOLUS_INFORMATION & 0xff)

func generatePacketBolusGetStepInformation() -> DanaGeneratePacket {
    return DanaGeneratePacket(opCode: DanaPacketType.OPCODE_BOLUS__GET_STEP_BOLUS_INFORMATION, data: nil)
}

func parsePacketBolusGetStepInformation(data: Data) -> DanaParsePacket<PacketBolusGetStepInformation> {
    let lastBolusTime = Calendar.current.date(bySettingHour: Int(data[DataStart + 4]), minute: Int(data[DataStart + 5]), second: 0, of: Date()) ?? Date()

    return DanaParsePacket(success: data[DataStart] == 0, data: PacketBolusGetStepInformation(
        bolusType: data[DataStart + 1],
        initialBolusAmount: Float(data.uint16(at: DataStart + 2)) / 100,
        lastBolusTime: lastBolusTime,
        lastBolusAmount: Float(data.uint16(at: DataStart + 6)) / 100,
        maxBolus: Float(data.uint16(at: DataStart + 8)) / 100,
        bolusStep: data[DataStart + 10]
    ))
}
