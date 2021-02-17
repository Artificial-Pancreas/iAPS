//
//  TenSomethingGlucoseEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/18/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class TenSomethingGlucoseEventTests: XCTestCase {
        
    func testDecoding() {
        let rawData = Data(hexadecimalString: "100bb40a0e010000")!
        let subject = TenSomethingGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        let expectedTimestamp = DateComponents(calendar: Calendar(identifier: .gregorian),
                                               year: 2014, month: 2, day: 10, hour: 11, minute: 52)
        XCTAssertEqual(subject.timestamp, expectedTimestamp)
    }
    
}
