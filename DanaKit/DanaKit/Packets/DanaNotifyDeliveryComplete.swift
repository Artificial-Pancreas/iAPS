//
//  DanaNotifyDeliveryComplete.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 13/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

struct PacketNotifyDeliveryComplete {
    var deliveredInsulin: Double
}

let CommandNotifyDeliveryComplete: UInt16 = (UInt16(DanaPacketType.TYPE_NOTIFY & 0xff) << 8) + UInt16(DanaPacketType.OPCODE_NOTIFY__DELIVERY_COMPLETE & 0xff)

func parsePacketNotifyDeliveryComplete(data: Data, usingUtc: Bool?) -> DanaParsePacket<PacketNotifyDeliveryComplete> {
    return DanaParsePacket(
        success: true,
        notifyType: CommandNotifyDeliveryComplete,
        rawData: data,
        data: PacketNotifyDeliveryComplete(
            deliveredInsulin: Double(data.uint16(at: DataStart)) / 100
        )
    )
}
