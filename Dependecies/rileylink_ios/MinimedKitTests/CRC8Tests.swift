//
//  CRC8Tests.swift
//  RileyLink
//
//  Created by Pete Schwamb on 2/27/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class CRC8Tests: XCTestCase {
       
    func testComputeCRC8() {
        let input = Data(hexadecimalString: "a259705504a24117043a0e080b003d3d00015b030105d817790a0f00000300008b1702000e080b0000")!
        XCTAssertEqual(0x71, input.crc8())
    }
}
