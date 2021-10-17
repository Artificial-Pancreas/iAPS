//
//  ChangeMaxBolusMessageBodyTests.swift
//  MinimedKitTests
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ChangeMaxBolusMessageBodyTests: XCTestCase {

    func testMaxBolus522() {
        let body = ChangeMaxBolusMessageBody(pumpModel: .model522, maxBolusUnits: 6.4)!

        XCTAssertEqual(Data(hexadecimalString: "0140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)
    }

    func testMaxBolus523() {
        let body = ChangeMaxBolusMessageBody(pumpModel: .model523, maxBolusUnits: 6.4)!

        XCTAssertEqual(Data(hexadecimalString: "0200400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)
    }

    func testMaxBolusRounded522() {
        let body = ChangeMaxBolusMessageBody(pumpModel: .model522, maxBolusUnits: 2.25)!

        XCTAssertEqual(Data(hexadecimalString: "0116000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)
    }


    func testMaxBolusRounded523() {
        let body = ChangeMaxBolusMessageBody(pumpModel: .model523, maxBolusUnits: 2.25)!

        XCTAssertEqual(Data(hexadecimalString: "0200160000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)
    }

    func testMaxBolusOutOfRange() {
        XCTAssertNil(ChangeMaxBolusMessageBody(pumpModel: .model522, maxBolusUnits: -1))
        XCTAssertNil(ChangeMaxBolusMessageBody(pumpModel: .model523, maxBolusUnits: 26))
    }
    
}
