//
//  PumpModelTests.swift
//  RileyLink
//
//  Created by Jaim Zuber on 2/24/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class PumpModelTests: XCTestCase {
    
    func test523AppendsSquareWaveToHistory() {
        XCTAssertTrue(PumpModel.model523.appendsSquareWaveToHistoryOnStartOfDelivery)
    }
    
    func test522DoesntAppendSquareWaveToHistory() {
        XCTAssertFalse(PumpModel.model522.appendsSquareWaveToHistoryOnStartOfDelivery)
    }
}
