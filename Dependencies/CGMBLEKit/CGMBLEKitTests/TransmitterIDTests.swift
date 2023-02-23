//
//  TransmitterIDTests.swift
//  xDripG5Tests
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import CGMBLEKit

class TransmitterIDTests: XCTestCase {

    /// Sanity check the hash computation path
    func testComputeHash() {
        let id = TransmitterID(id: "123456")

        XCTAssertEqual("e60d4a7999b0fbb2", id.computeHash(of: Data(hexadecimalString: "0123456789abcdef")!)!.hexadecimalString)
    }
    
}
