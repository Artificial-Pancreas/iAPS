//
//  SensorErrorGlucoseEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 12/6/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class SensorErrorGlucoseEventTests: XCTestCase {
    
    func testDecoding() {
        let rawData = Data(hexadecimalString: "0501")!
        let subject = SensorErrorGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        XCTAssertEqual(subject.dictionaryRepresentation["errorType"] as! String, "end")
    }
}
