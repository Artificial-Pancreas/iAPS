//
//  PayloadSplitterTest.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class PayloadSplitterTest: XCTestCase {
    func testSplitter() {
        let f1 = "00,01,54,57,10,23,03,00,00,c0,ff,ff,ff,fe,08,20,2e,a8,50,30".replacingOccurrences(of:",", with:"")
        let f2 = "01,04,bc,20,1f,f6,3d,00,01,a5,ff,ff,ff,fe,08,20,2e,a8,50,30".replacingOccurrences(of:",", with:"")
        let payload = Data(hexadecimalString: "54,57,10,23,03,00,00,c0,ff,ff,ff,fe,08,20,2e,a8,50,30,3d,00,01,a5".replacingOccurrences(of:",", with:""))!

        let splitter = PayloadSplitter(payload: payload)
        let packets = splitter.splitInPackets()

        assert(packets.count == 2)
        assert(f1 == packets[0].toData().hexadecimalString)
        let p2 = packets[1].toData().hexadecimalString
        assert(p2.count >= 10)

        assert(f2.substring(startIndex:0, toIndex:20) == p2.substring(startIndex: 0, toIndex: 20))
    }
    
}
