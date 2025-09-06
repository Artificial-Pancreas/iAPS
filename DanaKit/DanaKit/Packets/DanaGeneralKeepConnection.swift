//
//  DanaGeneralKeepConnection.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

let CommandGeneralKeepConnection: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_ETC__KEEP_CONNECTION & 0xff)

func generatePacketGeneralKeepConnection() -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_ETC__KEEP_CONNECTION,
        data: nil
    )
}

func parsePacketGeneralKeepConnection(data: Data, usingUtc: Bool?) -> DanaParsePacket<Any> {
    return DanaParsePacket(
        success: data[DataStart] == 0,
        rawData: data,
        data: nil
    )
}
