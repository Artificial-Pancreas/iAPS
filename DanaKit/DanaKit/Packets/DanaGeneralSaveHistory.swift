//
//  DanaGeneralSaveHistory.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralSaveHistory {
    var historyType: UInt8
    var historyDate: Date
    var historyCode: UInt8
    var historyValue: UInt16
}

let CommandGeneralSaveHistory: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_ETC__SET_HISTORY_SAVE & 0xff)

func generatePacketGeneralSaveHistory(options: PacketGeneralSaveHistory) -> DanaGeneratePacket {
    var data = Data(count: 10)
    data[0] = options.historyType
    data.addDate(at: 1, date: options.historyDate)

    data[7] = options.historyCode
    data[8] = UInt8(options.historyValue & 0xff)
    data[9] = UInt8((options.historyValue >> 8) & 0xff)

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_ETC__SET_HISTORY_SAVE,
        data: data
    )
}

func parsePacketGeneralSaveHistory(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
