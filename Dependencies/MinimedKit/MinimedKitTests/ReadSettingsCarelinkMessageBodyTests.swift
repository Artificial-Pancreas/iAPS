//
//  ReadSettingsCarelinkMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 12/26/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadSettingsCarelinkMessageBodyTests: XCTestCase {
    
    func testValidSettings() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7594040c01900010001010096008c00000000000064010400140019010101000000000000000000000000000000000000000000000000000000000000000000000000000000")!)
        
        if let message = message {
            XCTAssertTrue(message.messageBody is ReadSettingsCarelinkMessageBody)
            
            if let body = message.messageBody as? ReadSettingsCarelinkMessageBody {
                XCTAssertEqual(3.5, body.maxBasal)
                XCTAssertEqual(15, body.maxBolus)
                XCTAssertEqual(BasalProfile.standard, body.selectedBasalProfile)
                XCTAssertEqual(4, body.insulinActionCurveHours)
            }
            
        } else {
            XCTFail("Message is nil")
        }
    }

    func testValidSettings523() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7754838c0150003010100e505500000000000000164000400140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)
        
        if let message = message {
            XCTAssertTrue(message.messageBody is ReadSettingsCarelinkMessageBody)
            
            if let body = message.messageBody as? ReadSettingsCarelinkMessageBody {
                XCTAssertEqual(34, body.maxBasal)
                XCTAssertEqual(22.9, body.maxBolus)
                XCTAssertEqual(BasalProfile.standard, body.selectedBasalProfile)
                XCTAssertEqual(4, body.insulinActionCurveHours)
            }
            
        } else {
            XCTFail("Message is nil")
        }
    }

}
