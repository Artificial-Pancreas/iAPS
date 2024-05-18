//
//  DanaGeneralSetHistoryUploadMode.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralSetHistoryUploadMode {
    /**
       * 1 -> Turn on history upload mode, 0 -> turn off history upload mode.
       *
       * Need to do this before and after fetching the history from pump
       */
    var mode: UInt8
}

let CommandGeneralSetHistoryUploadMode: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_REVIEW__SET_HISTORY_UPLOAD_MODE & 0xff)

func generatePacketGeneralSetHistoryUploadMode(options: PacketGeneralSetHistoryUploadMode) -> DanaGeneratePacket {
    let data = Data([options.mode])

    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_REVIEW__SET_HISTORY_UPLOAD_MODE,
        data: data
    )
}

func parsePacketGeneralSetHistoryUploadMode(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
