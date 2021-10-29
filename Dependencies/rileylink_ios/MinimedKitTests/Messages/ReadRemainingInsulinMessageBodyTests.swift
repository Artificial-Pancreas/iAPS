//
//  ReadRemainingInsulinMessageBodyTests.swift
//  RileyLink
//
//  Created by Nathan Racklyeft on 5/25/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadRemainingInsulinMessageBodyTests: XCTestCase {
    
    func testReservoir723() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7594040730400000ca3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)

        let body = message?.messageBody as! ReadRemainingInsulinMessageBody

        XCTAssertEqual(80.875, body.getUnitsRemaining(insulinBitPackingScale: PumpModel.model723.insulinBitPackingScale))
    }

    func testReservoir522() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7578398730205460000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!)

        let body = message?.messageBody as! ReadRemainingInsulinMessageBody

        XCTAssertEqual(135.0, body.getUnitsRemaining(insulinBitPackingScale: PumpModel.model522.insulinBitPackingScale))
    }

}
