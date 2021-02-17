//
//  CRC8Tests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import OmniKit

class CRC8Tests: XCTestCase {
    
    func testComputeCRC8() {
        let input = Data(hexadecimalString: "1f07b1eeae1f07b1ee181f1a0eeb5701b202010a0101a000340034170d000208000186a0")!
        XCTAssertEqual(0x19, input.crc8())
    }
}

