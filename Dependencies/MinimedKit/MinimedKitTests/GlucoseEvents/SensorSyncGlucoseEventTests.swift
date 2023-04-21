//
//  SensorSyncGlucoseEventTests.swift
//  RileyLink
//
//  Created by Timothy Mecklem on 10/18/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class SensorSyncGlucoseEventTests: XCTestCase {
    
    func testSyncTypeNew() {
        let rawData = Data(hexadecimalString: "0d4d44330f")!
        let subject = SensorSyncGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        let expectedTimestamp = DateComponents(calendar: Calendar(identifier: .gregorian),
                                               year: 2015, month: 5, day: 19, hour: 13, minute: 04)
        XCTAssertEqual(subject.timestamp, expectedTimestamp)
        XCTAssertEqual(subject.dictionaryRepresentation["syncType"] as! String, "new")
    }
    
    func testSyncTypeOld() {
        let rawData = Data(hexadecimalString: "0d4d44530f")!
        let subject = SensorSyncGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        let expectedTimestamp = DateComponents(calendar: Calendar(identifier: .gregorian),
                                               year: 2015, month: 5, day: 19, hour: 13, minute: 04)
        XCTAssertEqual(subject.timestamp, expectedTimestamp)
        XCTAssertEqual(subject.dictionaryRepresentation["syncType"] as! String, "old")
    }
    
    func testSyncTypeFind() {
        let rawData = Data(hexadecimalString: "0d4d44730f")!
        let subject = SensorSyncGlucoseEvent(availableData: rawData, relativeTimestamp: DateComponents())!
        
        let expectedTimestamp = DateComponents(calendar: Calendar(identifier: .gregorian),
                                               year: 2015, month: 5, day: 19, hour: 13, minute: 04)
        XCTAssertEqual(subject.timestamp, expectedTimestamp)
        XCTAssertEqual(subject.dictionaryRepresentation["syncType"] as! String, "find")
    }
    
}
