//
//  PodStateTests.swift
//  OmniBLE
//
//  Created by Pete Schwamb on 10/13/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//  From OmniKitTests/PodStateTests.swift
//

import XCTest
@testable import OmniBLE

class PodStateTests: XCTestCase {
    
    func testErrorResponse() {
        do {
            let errorResponse = try ErrorResponse(encodedData: Data(hexadecimalString: "0603070008019a")!)

            switch errorResponse.errorResponseType {
            case .nonretryableError(let errorCode, let faultEventCode, let podProgress):
                XCTAssertEqual(7, errorCode)
                XCTAssertEqual(.noFaults, faultEventCode.faultType)
                XCTAssertEqual(.aboveFiftyUnits, podProgress)
                break
            default:
                XCTFail("Unexpected bad nonce response")
                break
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
}

