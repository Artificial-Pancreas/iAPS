//
//  NSDataTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/5/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class NSDataTests: XCTestCase {
        
    func testInitWithHexadecimalStringEmpty() {
        let data = Data(hexadecimalString: "")
        XCTAssertEqual(0, data!.count)
    }
    
    func testInitWithHexadecimalStringOdd() {
        let data = Data(hexadecimalString: "a")
        XCTAssertNil(data)
    }
    
    func testInitWithHexadecimalStringZeros() {
        let data = Data(hexadecimalString: "00")
        XCTAssertEqual(1, data!.count)
        
        var bytes = [UInt8](repeating: 1, count: 1)
        data?.copyBytes(to: &bytes, count: 1)
        XCTAssertEqual(0, bytes[0])
    }
    
    func testInitWithHexadecimalStringShortData() {
        let data = Data(hexadecimalString: "a2594040")
        
        XCTAssertEqual(4, data!.count)
        
        var bytes = [UInt8](repeating: 0, count: 4)
        data?.copyBytes(to: &bytes, count: 4)
        XCTAssertEqual([0xa2, 0x59, 0x40, 0x40], bytes)
    }
}
