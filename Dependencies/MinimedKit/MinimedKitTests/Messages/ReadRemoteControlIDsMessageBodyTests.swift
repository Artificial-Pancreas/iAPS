//
//  ReadRemoteControlIDsMessageBodyTests.swift
//  MinimedKitTests
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadRemoteControlIDsMessageBodyTests: XCTestCase {

    func testDecodeOneRemote() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a759404076123132333435362d2d2d2d2d2d2d2d2d2d2d2d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)!

        let body = message.messageBody as! ReadRemoteControlIDsMessageBody

        XCTAssertEqual(1, body.ids.count)
        XCTAssertEqual(Data([1, 2, 3, 4, 5, 6]), body.ids[0])
    }


    func testDecodeZeroRemotes() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a759404076122d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d2d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)!

        let body = message.messageBody as! ReadRemoteControlIDsMessageBody

        XCTAssertEqual(0, body.ids.count)
    }

    func testDecodeThreeRemotes() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7594040761230303030303031303031303039393939393900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)!

        let body = message.messageBody as! ReadRemoteControlIDsMessageBody

        XCTAssertEqual(3, body.ids.count)
        XCTAssertEqual(Data([0, 0, 0, 0, 0, 0]), body.ids[0])
        XCTAssertEqual(Data([1, 0, 0, 1, 0, 0]), body.ids[1])
        XCTAssertEqual(Data([9, 9, 9, 9, 9, 9]), body.ids[2])
    }

}
