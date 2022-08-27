//
//  PayloadSplitter.swift
//  OmniBLE
//
//  Created by Randall Knutson on 8/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import CryptoSwift

class PayloadSplitter {
    private let payload: Data
    
    init(payload: Data) {
        self.payload = payload
    }
    
    func splitInPackets() -> Array<BlePacket> {
        if (payload.count <= FirstBlePacket.CAPACITY_WITH_THE_OPTIONAL_PLUS_ONE_PACKET) {
            return splitInOnePacket()
        }
        var ret = Array<BlePacket>()
        let crc32 = payload.crc32()
        let middleFragments = (payload.count - FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS) / MiddleBlePacket.CAPACITY
        let rest = UInt8((payload.count - middleFragments * MiddleBlePacket.CAPACITY) - FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS)
        ret.append(
            FirstBlePacket(
                fullFragments: middleFragments + 1,
                payload: payload.subdata(in: 0..<FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS)
            )
        )
        if (middleFragments > 0) {
            for i in 1...middleFragments {
                let p = payload.subdata(in: (FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS + (i - 1) * MiddleBlePacket.CAPACITY)..<(FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS + i * MiddleBlePacket.CAPACITY))
                ret.append(
                    MiddleBlePacket(
                        index: UInt8(i),
                        payload: p
                    )
                )
            }
        }
        let end = min(LastBlePacket.CAPACITY, Int(rest))
        ret.append(
            LastBlePacket(
                index: UInt8(middleFragments + 1),
                size: rest,
                payload: payload.subdata(in: middleFragments * MiddleBlePacket.CAPACITY + FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS..<middleFragments * MiddleBlePacket.CAPACITY + FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS + end),
                crc32: crc32
            )
        )
        if (rest > LastBlePacket.CAPACITY) {
            ret.append(
                LastOptionalPlusOneBlePacket(
                    index: UInt8(middleFragments + 2),
                    payload: payload.subdata(in: middleFragments * MiddleBlePacket.CAPACITY + FirstBlePacket.CAPACITY_WITH_MIDDLE_PACKETS + LastBlePacket.CAPACITY..<payload.count),
                    size: UInt8(Int(rest) - LastBlePacket.CAPACITY)
                )
            )
        }
        return ret
    }

    private func splitInOnePacket() -> Array<BlePacket> {
        var ret = Array<BlePacket>()
        let crc32 = payload.crc32()
        let end = min(FirstBlePacket.CAPACITY_WITHOUT_MIDDLE_PACKETS, payload.count)
        ret.append(
            FirstBlePacket(
                fullFragments: 0,
                payload: payload.subdata(in: 0..<end),
                size: UInt8(payload.count),
                crc32: crc32
            )
        )
        if (payload.count > FirstBlePacket.CAPACITY_WITHOUT_MIDDLE_PACKETS) {
            ret.append(
                LastOptionalPlusOneBlePacket(
                    index: 1,
                    payload: payload.subdata(in: end..<payload.count),
                    size: UInt8(payload.count - end)
                )
            )
        }
        return ret
    }
}
