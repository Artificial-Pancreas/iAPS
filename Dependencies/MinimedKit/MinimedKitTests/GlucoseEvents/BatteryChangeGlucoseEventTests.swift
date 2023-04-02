//
//  BatteryChangeGlucoseEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/18/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class BatteryChangeGlucoseEventTests: XCTestCase {
    
    func testDecoding() {
        let rawData = Data(hexadecimalString: "0a0bae0a0e")!
        let subject = BatteryChangeGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        let expectedTimestamp = DateComponents(calendar: Calendar(identifier: .gregorian),
                                               year: 2014, month: 2, day: 10, hour: 11, minute: 46)
        XCTAssertEqual(subject.timestamp, expectedTimestamp)
    }
}
