//
//  PayloadJoinerTest.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class PayloadJoinerTest: XCTestCase {
    
    func testJoiner() {

        let f1 = Data(hexadecimalString: "00,01,54,57,10,23,03,00,00,c0,ff,ff,ff,fe,08,20,2e,a8,50,30".replacingOccurrences(of: ",", with: ""))!
        let f2 = Data(hexadecimalString: "01,04,bc,20,1f,f6,3d,00,01,a5,ff,ff,ff,fe,08,20,2e,a8,50,30".replacingOccurrences(of: ",", with: ""))!
        
        let payload = "54,57,10,23,03,00,00,c0,ff,ff,ff,fe,08,20,2e,a8,50,30,3d,00,01,a5".replacingOccurrences(of: ",", with: "")
        let joiner = try! PayloadJoiner(firstPacket: f1)
        try! joiner.accumulate(packet: f2)
        let actual = try! joiner.finalize()
        assert(payload == actual.hexadecimalString)
    }
}
