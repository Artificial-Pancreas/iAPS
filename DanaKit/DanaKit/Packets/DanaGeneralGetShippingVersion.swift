//
//  DanaGeneralGetShippingVersion.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketGeneralGetShippingVersion {
    var bleModel: String
}

let CommandGeneralGetShippingVersion: UInt16 = (UInt16(DanaPacketType.TYPE_RESPONSE & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_GENERAL__GET_SHIPPING_VERSION & 0xff)

func generatePacketGeneralGetShippingVersion() -> DanaGeneratePacket {
    return DanaGeneratePacket(
        opCode: DanaPacketType.OPCODE_GENERAL__GET_SHIPPING_VERSION,
        data: nil
    )
}

func parsePacketGeneralGetShippingVersion(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketGeneralGetShippingVersion> {
    return DanaParsePacket(
        success: true,
        rawData: data,
        data: PacketGeneralGetShippingVersion(
            bleModel: String(data: data.subdata(in: DataStart..<data.count), encoding: .utf8) ?? ""
        )
    )
}
