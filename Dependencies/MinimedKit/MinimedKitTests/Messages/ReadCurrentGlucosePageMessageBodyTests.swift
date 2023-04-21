//
//  ReadCurrentGlucosePageMessageBodyTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/19/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadCurrentGlucosePageMessageBodyTests: XCTestCase {
    
    func testResponseInitializer() {
        var responseData = Data(hexadecimalString: "0000000D6100100020")!
        responseData.append(contentsOf: [UInt8](repeating: 0, count: 65 - responseData.count))
        
        let messageBody = ReadCurrentGlucosePageMessageBody(rxData: responseData)!
        
        XCTAssertEqual(messageBody.pageNum, 3425)
        XCTAssertEqual(messageBody.glucose, 16)
        XCTAssertEqual(messageBody.isig, 32)
    }
    
}
