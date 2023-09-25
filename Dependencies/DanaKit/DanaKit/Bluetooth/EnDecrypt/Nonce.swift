//
//  Nonce.swift
//  OmniBLE
//
//  Created by Randall Knutson on 11/4/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

class Nonce {
    let prefix: Data
    
    init (prefix: Data) {
        guard prefix.count == 8 else { fatalError("Nonce prefix should be 8 bytes long") }
        self.prefix = prefix
    }

    func toData(sqn: Int, podReceiving: Bool) -> Data {
        var ret = Data(bigEndian: sqn)
            .subdata(in: 3..<8)
        if (podReceiving) {
            ret[0] = UInt8(ret[0] & 127)
        } else {
            ret[0] = UInt8(ret[0] | 128)
        }
        return prefix + ret
    }
}
