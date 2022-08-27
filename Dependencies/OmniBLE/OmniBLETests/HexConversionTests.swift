//
//  HexConversionTests.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class HexConversionTests: XCTestCase {
    
    func testConversion(){
        let hexString = "00,01,54,57,10,23,03,00,00,c0,ff,ff,ff,fe,08,20,2e,a8,50,30".replacingOccurrences(of: ",", with: "")
        let f1 = Data(hexadecimalString: hexString)!
        assert(f1.hexadecimalString == hexString)
    }
}
