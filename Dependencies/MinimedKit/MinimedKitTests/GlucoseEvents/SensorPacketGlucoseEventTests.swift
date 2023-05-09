//
//  SensorPacketGlucoseEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/6/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class SensorPacketGlucoseEventTests: XCTestCase {
    
    func testDecoding() {
        let rawData = Data(hexadecimalString: "0402")!
        let subject = SensorPacketGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        XCTAssertEqual(subject.dictionaryRepresentation["packetType"] as! String, "init")
    }
}
