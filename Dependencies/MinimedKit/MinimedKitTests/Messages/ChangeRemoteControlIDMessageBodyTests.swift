//
//  ChangeRemoteControlIDMessageBodyTests.swift
//  MinimedKitTests
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ChangeRemoteControlIDMessageBodyTests: XCTestCase {

    func testEncodeOneRemote() {
        let expected = Data(hexadecimalString: "0700313233343536000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!
        let body = ChangeRemoteControlIDMessageBody(id: Data([1, 2, 3, 4, 5, 6]), index: 0)!

        XCTAssertEqual(expected, body.txData, body.txData.hexadecimalString)
    }


    func testEncodeZeroRemotes() {
        let expected = Data(hexadecimalString: "07022d2d2d2d2d2d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!
        let body = ChangeRemoteControlIDMessageBody(id: nil, index: 2)!

        XCTAssertEqual(expected, body.txData)
    }

}
