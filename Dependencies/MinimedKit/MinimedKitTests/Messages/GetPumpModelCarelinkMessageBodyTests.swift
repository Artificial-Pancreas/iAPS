//
//  GetPumpModelCarelinkMessageBodyTests.swift
//  RileyLink
//
//  Created by Pete Schwamb on 3/14/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class GetPumpModelCarelinkMessageBodyTests: XCTestCase {
    
    func testValidGetModelResponse() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a73505358d0903353233000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)
        
        if let message = message {
            XCTAssertTrue(message.messageBody is GetPumpModelCarelinkMessageBody)
            let body = message.messageBody as! GetPumpModelCarelinkMessageBody
            XCTAssertEqual(body.model, "523")
        } else {
            XCTFail("\(String(describing: message)) is nil")
        }
    }
    
}
