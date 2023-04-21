//
//  CRC16Tests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import OmniKit

class CRC16Tests: XCTestCase {

    func testComputeCRC16() {
        let input = Data(hexadecimalString: "1f01482a10030e0100")!
        XCTAssertEqual(0x802c, input.crc16())
    }
}



