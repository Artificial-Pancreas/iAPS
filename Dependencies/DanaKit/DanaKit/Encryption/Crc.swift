//
//  Crc.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 06/12/2023.
//  Copyright © 2023 Randall Knutson. All rights reserved.
//

import Foundation

func generateCrc(buffer: Data, enhancedEncryption: UInt8, isEncryptionCommand: Bool) -> UInt16 {
    var crc: UInt16 = 0

    for byte in buffer {
        var result = ((crc >> 8) | (crc << 8)) ^ UInt16(byte)
        result ^= (result & 0xff) >> 4
        result ^= (result << 12)

        if enhancedEncryption == 0 {
            let tmp = (result & 0xff) << 3 | ((result & 0xff) >> 2) << 5
            result ^= tmp
        } else if enhancedEncryption == 1 {
            var tmp: UInt16 = 0
            if isEncryptionCommand {
                tmp = (result & 0xff) << 3 | ((result & 0xff) >> 2) << 5
            } else {
                tmp = (result & 0xff) << 5 | ((result & 0xff) >> 4) << 2
            }
            result ^= tmp
        } else if enhancedEncryption == 2 {
            var tmp: UInt16 = 0
            if isEncryptionCommand {
                tmp = (result & 0xff) << 3 | ((result & 0xff) >> 2) << 5
            } else {
                tmp = (result & 0xff) << 4 | ((result & 0xff) >> 3) << 2
            }
            result ^= tmp
        }

        crc = result
    }

    return crc
}
