//
//  MeterMessageTests.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/10/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class MeterMessageTests: XCTestCase {
        
    func testValidMeterMessage() {
        let message = MeterMessage(rxData: Data(hexadecimalString: "a5c527ad018e77")!)
        
        if let message = message {
            XCTAssertEqual(message.glucose, 257)
            XCTAssertEqual(message.ackFlag, false)
        } else {
            XCTFail("\(String(describing: message)) is nil")
        }
    }
    
}
