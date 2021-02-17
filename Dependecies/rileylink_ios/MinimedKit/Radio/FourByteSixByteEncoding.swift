//
//  FourByteSixByteEncoding.swift
//  RileyLink
//
//  Created by Pete Schwamb on 2/27/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import Foundation

fileprivate let codes = [21, 49, 50, 35, 52, 37, 38, 22, 26, 25, 42, 11, 44, 13, 14, 28]

fileprivate let codesRev = Dictionary<Int, UInt8>(uniqueKeysWithValues: codes.enumerated().map({ ($1, UInt8($0)) }))

public extension Sequence where Element == UInt8 {

    func decode4b6b() -> [UInt8]? {
        var buffer = [UInt8]()
        var availBits = 0
        var bitAccumulator = 0
        for byte in self {
            if byte == 0 {
                break
            }
            
            bitAccumulator = (bitAccumulator << 8) + Int(byte)
            availBits += 8
            if availBits >= 12 {
                guard let hiNibble = codesRev[bitAccumulator >> (availBits - 6)],
                      let loNibble = codesRev[(bitAccumulator >> (availBits - 12)) & 0b111111]
                else {
                    return nil
                }
                let decoded = UInt8((hiNibble << 4) + loNibble)
                buffer.append(decoded)
                availBits -= 12
                bitAccumulator = bitAccumulator & (0xffff >> (16-availBits))
            }
        }
        return buffer
    }
    
    func encode4b6b() -> [UInt8] {
        var buffer = [UInt8]()
        var bitAccumulator = 0x0
        var bitcount = 0
        for byte in self {
            bitAccumulator <<= 6
            bitAccumulator |= codes[Int(byte >> 4)]
            bitcount += 6
            
            bitAccumulator <<= 6
            bitAccumulator |= codes[Int(byte & 0x0f)]
            bitcount += 6
            
            while bitcount >= 8 {
                buffer.append(UInt8(bitAccumulator >> (bitcount-8)) & 0xff)
                bitcount -= 8
                bitAccumulator &= (0xffff >> (16-bitcount))
            }
        }
        if bitcount > 0 {
            bitAccumulator <<= (8-bitcount)
            buffer.append(UInt8(bitAccumulator) & 0xff)
        }
        return buffer
    }
}

