//
//  PayloadJoiner.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

class PayloadJoiner {
    var oneExtraPacket: Bool
    let fullFragments: Int
    var crc: Data?
    private var expectedIndex = 0
    private var fragments: Array<BlePacket> = Array<BlePacket>()

    init(firstPacket: Data) throws {
        let firstPacket = try FirstBlePacket.parse(payload: firstPacket)
        fragments.append(firstPacket)
        fullFragments = firstPacket.fullFragments
        crc = firstPacket.crc32
        oneExtraPacket = firstPacket.oneExtraPacket
    }

    func accumulate(packet: Data) throws {
        if (packet.count < 3) { // idx, size, at least 1 byte of payload
            throw PodProtocolError.incorrectPacketException(packet, (expectedIndex + 1))
        }
        let idx = Int(packet[0])
        if (idx != expectedIndex + 1) {
            throw PodProtocolError.incorrectPacketException(packet, (expectedIndex + 1))
        }
        expectedIndex += 1
        switch idx{
        case let index where index < fullFragments:
            fragments.append(try MiddleBlePacket.parse(payload: packet))
        case let index where index == fullFragments:
            let lastPacket = try LastBlePacket.parse(payload: packet)
            fragments.append(lastPacket)
            crc = lastPacket.crc32
            oneExtraPacket = lastPacket.oneExtraPacket
        case let index where index == fullFragments + 1 && oneExtraPacket:
            fragments.append(try LastOptionalPlusOneBlePacket.parse(payload: packet))
        case let index where index > fullFragments:
            throw PodProtocolError.incorrectPacketException(packet, idx)
        default:
            throw PodProtocolError.incorrectPacketException(packet, idx)
        }
    }

    func finalize() throws -> Data {
        let payloads = fragments.map { x in x.payload }
        let bb = payloads.reduce(Data(), { acc, elem in acc + elem })
        let computedCrc32 = bb.crc32()
        if let crc32 = crc, crc32 != computedCrc32 {
            throw PodProtocolError.invalidCrc(payloadCrc: crc32, computedCrc: computedCrc32)
        }
        return bb
    }
}
