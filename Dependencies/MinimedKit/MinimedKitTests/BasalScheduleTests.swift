//
//  BasalScheduleTests.swift
//  RileyLink
//
//  Created by Jaim Zuber on 5/2/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class BasalScheduleTests: XCTestCase {

    var sampleData: Data {
        let sampleDataString = "06000052000178050202000304000402000504000602000704000802000904000a02000b04000c02000d02000e02000f040010020011040012020013040014020015040016020017040018020019000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

        return Data(hexadecimalString: sampleDataString)!
    }

    func testBasicConversion() {
        let profile = BasalSchedule(rawValue: sampleData)!
        
        XCTAssertEqual(profile.entries.count, 26)
        
        let basalSchedule = profile.entries
        
        // Test each element
        XCTAssertEqual(basalSchedule[0].index, 0)
        XCTAssertEqual(basalSchedule[0].timeOffset, TimeInterval(minutes: 0))
        XCTAssertEqual(basalSchedule[0].rate, 0.15, accuracy: .ulpOfOne)
        
        XCTAssertEqual(basalSchedule[1].index, 1)
        XCTAssertEqual(basalSchedule[1].timeOffset, TimeInterval(minutes: 30))
        XCTAssertEqual(basalSchedule[1].rate, 2.05, accuracy: .ulpOfOne)
        
        // Tests parsing rates that take two bytes to encode
        XCTAssertEqual(basalSchedule[2].index, 2)
        XCTAssertEqual(basalSchedule[2].timeOffset, TimeInterval(minutes: 60))
        XCTAssertEqual(basalSchedule[2].rate, 35.00, accuracy: .ulpOfOne)
        
        // Tests parsing entry on the second page
        XCTAssertEqual(basalSchedule[25].index, 25)
        XCTAssertEqual(basalSchedule[25].timeOffset, TimeInterval(minutes: 750))
        XCTAssertEqual(basalSchedule[25].rate, 0.05, accuracy: .ulpOfOne)

        XCTAssertEqual(sampleData.hexadecimalString, profile.rawValue.hexadecimalString)
    }

    func testTxData() {
        let profile = BasalSchedule(entries: [
            BasalScheduleEntry(index: 0, timeOffset: .hours(0), rate: 1.0),
            BasalScheduleEntry(index: 1, timeOffset: .hours(4), rate: 2.0),
        ])

        XCTAssertEqual("280000500008000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", profile.rawValue.hexadecimalString)
    }

    func testDataFrameParsing() {
        let frames = DataFrameMessageBody.dataFramesFromContents(sampleData)

        XCTAssertEqual("0106000052000178050202000304000402000504000602000704000802000904000a02000b04000c02000d02000e02000f04001002001104001202001304001402", frames[0].txData.hexadecimalString)
        XCTAssertEqual("0200150400160200170400180200190000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", frames[1].txData.hexadecimalString)
        XCTAssertEqual("8300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", frames[2].txData.hexadecimalString)

        XCTAssertEqual(3, frames.count)
    }

    func testEmptySchedule() {
        let emptyData = Data(hexadecimalString: "00003f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!

        let profile = BasalSchedule(rawValue: emptyData)
        XCTAssertNil(profile)

        XCTAssertEqual(emptyData, BasalSchedule(entries: []).rawValue)
    }
}
