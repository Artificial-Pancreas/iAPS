//
//  TransmitterTimeRxMessageTests.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 6/4/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import CGMBLEKit

/// Thanks to https://github.com/mthatcher for the fixtures!
class TransmitterTimeRxMessageTests: XCTestCase {

    func testNoSession() {
        var data = Data(hexadecimalString: "2500e8f87100ffffffff010000000a70")!
        var message = TransmitterTimeRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(7469288, message.currentTime)
        XCTAssertEqual(0xffffffff, message.sessionStartTime)

        data = Data(hexadecimalString: "250096fd7100ffffffff01000000226d")!
        message = TransmitterTimeRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(7470486, message.currentTime)
        XCTAssertEqual(0xffffffff, message.sessionStartTime)

        data = Data(hexadecimalString: "2500eeff7100ffffffff010000008952")!
        message = TransmitterTimeRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(7471086, message.currentTime)
        XCTAssertEqual(0xffffffff, message.sessionStartTime)
    }

    func testInSession() {
        var data = Data(hexadecimalString: "2500470272007cff710001000000fa1d")!
        var message = TransmitterTimeRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(7471687, message.currentTime)
        XCTAssertEqual(7470972, message.sessionStartTime)

        data = Data(hexadecimalString: "2500beb24d00f22d4d000100000083c0")!
        message = TransmitterTimeRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(5092030, message.currentTime)
        XCTAssertEqual(5058034, message.sessionStartTime)
    }
}
