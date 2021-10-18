//
//  SensorDataLowEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/5/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class SensorDataLowGlucoseEventTests: XCTestCase {
    
    func testDecoding() {
        let rawData = Data(hexadecimalString: "06")!
        let subject = SensorDataLowGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        XCTAssertEqual(subject.sgv, 40)
    }
    
}
