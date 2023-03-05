//
//  SessionStartRxMessageTests.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 6/4/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import CGMBLEKit

/// Thanks to https://github.com/mthatcher for the fixtures!
class SessionStartRxMessageTests: XCTestCase {

    func testSuccessfulStart() {
        var data = Data(hexadecimalString: "2700014bf871004bf87100e9f8710095d9")!
        var message = SessionStartRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(1, message.received)
        XCTAssertEqual(7469131, message.requestedStartTime)
        XCTAssertEqual(7469131, message.sessionStartTime)
        XCTAssertEqual(7469289, message.transmitterTime)

        data = Data(hexadecimalString: "2700012bfd71002bfd710096fd71000f6a")!
        message = SessionStartRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(1, message.received)
        XCTAssertEqual(7470379, message.requestedStartTime)
        XCTAssertEqual(7470379, message.sessionStartTime)
        XCTAssertEqual(7470486, message.transmitterTime)

        data = Data(hexadecimalString: "2700017cff71007cff7100eeff7100aeed")!
        message = SessionStartRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(1, message.received)
        XCTAssertEqual(7470972, message.requestedStartTime)
        XCTAssertEqual(7470972, message.sessionStartTime)
        XCTAssertEqual(7471086, message.transmitterTime)
    }

}
