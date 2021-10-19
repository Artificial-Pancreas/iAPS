//
//  SensorDataHighGlucoseEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/6/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class SensorDataHighGlucoseEventTests: XCTestCase {
        
    func testDecoding() {
        let rawData = Data(hexadecimalString: "07FF")!
        let subject = SensorDataHighGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        XCTAssertEqual(subject.sgv, 400)
    }
    
}
