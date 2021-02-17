//
//  DeviceLinkMessageBodyTests.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/7/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class DeviceLinkMessageBodyTests: XCTestCase {
        
    func testValidDeviceLinkMessage() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a23505350a93ce8aa000")!)
        
        if let message = message {
            XCTAssertTrue(message.messageBody is DeviceLinkMessageBody)
        } else {
            XCTFail("\(String(describing: message)) is nil")
        }
    }
    
    func testMidnightSensor() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a23505350a93ce8aa000")!)!
        
        let body = message.messageBody as! DeviceLinkMessageBody
        
        XCTAssertEqual(body.sequence, 19)
        XCTAssertEqual(body.deviceAddress.hexadecimalString, "ce8aa0")
    }
}
