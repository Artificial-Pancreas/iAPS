//
//  ChangeTempBasalCarelinkMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/6/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit


class ChangeTempBasalCarelinkMessageBodyTests: XCTestCase {
    
    func testTempBasalMessageBody() {
        let message = PumpMessage(packetType: .carelink, address: "123456", messageType: .changeTempBasal, messageBody: ChangeTempBasalCarelinkMessageBody(unitsPerHour: 1.1, duration: TimeInterval(30 * 60)))
        
        XCTAssertEqual(
            Data(hexadecimalString: "a71234564C03002C0100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }
    
    func testTempBasalMessageBodyLarge() {
        let message = PumpMessage(packetType: .carelink, address: "123456", messageType: .changeTempBasal, messageBody: ChangeTempBasalCarelinkMessageBody(unitsPerHour: 6.5, duration: TimeInterval(150 * 60)))
        
        XCTAssertEqual(
            Data(hexadecimalString: "a71234564C0301040500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }
    
    func testTempBasalMessageBodyRounding() {
        let message = PumpMessage(packetType: .carelink, address: "123456", messageType: .changeTempBasal, messageBody: ChangeTempBasalCarelinkMessageBody(unitsPerHour: 1.442, duration: TimeInterval(65.5 * 60)))
        
        XCTAssertEqual(
            Data(hexadecimalString: "a71234564C0300390200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
            message.txData
        )
    }
    
}
