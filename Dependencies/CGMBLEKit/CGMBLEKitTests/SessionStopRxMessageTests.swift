//
//  SessionStopRxMessageTests.swift
//  xDripG5
//
//  Created by Nathan Racklyeft on 6/4/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import CGMBLEKit

/// Thanks to https://github.com/mthatcher for the fixtures!
class SessionStopRxMessageTests: XCTestCase {
    
    func testSuccessfulStop() {
        var data = Data(hexadecimalString: "29000128027200ffffffff47027200ba85")!
        var message = SessionStopRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(1, message.received)
        XCTAssertEqual(7471656, message.sessionStopTime)
        XCTAssertEqual(0xffffffff, message.sessionStartTime)
        XCTAssertEqual(7471687, message.transmitterTime)

        data = Data(hexadecimalString: "2900013ffe7100ffffffffc2fe71008268")!
        message = SessionStopRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(1, message.received)
        XCTAssertEqual(7470655, message.sessionStopTime)
        XCTAssertEqual(0xffffffff, message.sessionStartTime)
        XCTAssertEqual(7470786, message.transmitterTime)

        data = Data(hexadecimalString: "290001f5fb7100ffffffff6afc7100fa8a")!
        message = SessionStopRxMessage(data: data)!

        XCTAssertEqual(0, message.status)
        XCTAssertEqual(1, message.received)
        XCTAssertEqual(7470069, message.sessionStopTime)
        XCTAssertEqual(0xffffffff, message.sessionStartTime)
        XCTAssertEqual(7470186, message.transmitterTime)
    }
    
}
