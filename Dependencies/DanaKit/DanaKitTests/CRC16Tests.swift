//
//  CRC16Tests.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//  From OmniKitTests/CRC16Tests.swift
//

import XCTest
@testable import OmniBLE

class CRC16Tests: XCTestCase {

    func testComputeCRC16() {
        let input = Data(hexadecimalString: "1f01482a10030e0100")!
        XCTAssertEqual(0x802c, input.crc16())
    }
}



