//
//  BolusNormalPumpEventTests.swift
//  RileyLink
//
//  Created by Jaim Zuber on 3/8/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import XCTest

@testable import MinimedKit

class BolusNormalPumpEventTests: XCTestCase {
    
    let data523 = Data(hexadecimalString: "01009000900058008a344b1010")!
    
    var bolusPumpEvent523: BolusNormalPumpEvent!
    
    override func setUp() {
        super.setUp()
        bolusPumpEvent523 = BolusNormalPumpEvent(availableData: data523, pumpModel: PumpModel.model523)!
    }
    
    func test523Year() {
        XCTAssertEqual(bolusPumpEvent523.timestamp.year, 2016)
    }
    
    func test523Month() {
        XCTAssertEqual(bolusPumpEvent523.timestamp.month, 8)
    }
    
    func test523RawData() {
        XCTAssertEqual(bolusPumpEvent523.rawData, data523)
    }
    
    func test523Duration() {
        XCTAssertEqual(bolusPumpEvent523.duration, 0.0)
    }
    
    func test523Length() {
        XCTAssertEqual(bolusPumpEvent523.length, 13)
    }
    
    func test523Type() {
        XCTAssertEqual(bolusPumpEvent523.type, .normal)
    }
    
    func test523UnabsorbedInsulinTotal() {
        XCTAssertEqual(bolusPumpEvent523.unabsorbedInsulinTotal, 2.2)
    }
    
    func test523Programmed() {
        XCTAssertEqual(bolusPumpEvent523.programmed, 3.6)
    }
    
    func test523Amount() {
        XCTAssertEqual(bolusPumpEvent523.amount, 3.6)
    }
}
