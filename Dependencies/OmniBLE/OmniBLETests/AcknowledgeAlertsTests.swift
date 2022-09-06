//
//  AcknowledgeAlertsTests.swift
//  OmniBLE
//
//  Created by Eelke Jager on 18/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//  From OmniKitTests/AcknowledgeAlertsTests.swift
//
import Foundation

import XCTest
@testable import OmniBLE

class AcknowledgeAlertsTests: XCTestCase {
    func testAcknowledgeLowReservoirAlert() {
        // 11 05 2f9b5b2f 10
        do {
            // Encode
            let encoded = AcknowledgeAlertCommand(nonce: 0x2f9b5b2f, alerts: AlertSet(rawValue: 0x10))
            XCTAssertEqual("11052f9b5b2f10", encoded.data.hexadecimalString)
            
            // Decode
            let cmd = try AcknowledgeAlertCommand(encodedData: Data(hexadecimalString: "11052f9b5b2f10")!)
            XCTAssertEqual(.acknowledgeAlert,cmd.blockType)
            XCTAssertEqual(0x2f9b5b2f, cmd.nonce)
            XCTAssert(cmd.alerts.contains(.slot4))
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
}
