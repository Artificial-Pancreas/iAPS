//
//  ReadTempBasalCarelinkMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit


class ReadTempBasalCarelinkMessageBodyTests: XCTestCase {
    
    func testReadTempBasal() {
        // 06 00 00 00 37 00 17  -> 1.375 U @ 23 min remaining
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7123456980600000037001700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)!
        
        let body = message.messageBody as! ReadTempBasalCarelinkMessageBody
        
        XCTAssertEqual(TimeInterval(23 * 60), body.timeRemaining)
        XCTAssertEqual(1.375, body.rate)
        XCTAssertEqual(ReadTempBasalCarelinkMessageBody.RateType.absolute, body.rateType)
    }
    
    func testReadTempBasalZero() {
        // 06 00 00 00 00 00 1d  -> 0 U @ 29 min remaining
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7123456980600000000001d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)!
        
        let body = message.messageBody as! ReadTempBasalCarelinkMessageBody
        
        XCTAssertEqual(TimeInterval(29 * 60), body.timeRemaining)
        XCTAssertEqual(0, body.rate)
        XCTAssertEqual(ReadTempBasalCarelinkMessageBody.RateType.absolute, body.rateType)
    }
    
    func testReadHighTempBasalRate() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7754838980600000550001e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)!
        
        let body = message.messageBody as! ReadTempBasalCarelinkMessageBody
        
        XCTAssertEqual(TimeInterval(30 * 60), body.timeRemaining)
        XCTAssertEqual(34, body.rate)
        XCTAssertEqual(ReadTempBasalCarelinkMessageBody.RateType.absolute, body.rateType)
    }
}
