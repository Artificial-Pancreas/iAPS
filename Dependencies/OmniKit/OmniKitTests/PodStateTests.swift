//
//  PodStateTests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 10/13/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import OmniKit

class PodStateTests: XCTestCase {

    func testNonceValues() {
        var podState = PodState(address: 0x1f000000, pmVersion: "1.1.0", piVersion: "1.1.0", lot: 42560, tid: 661771, insulinType: .novolog)
        
        XCTAssertEqual(podState.currentNonce, 0x8c61ee59)
        podState.advanceToNextNonce()
        XCTAssertEqual(podState.currentNonce, 0xc0256620)
        podState.advanceToNextNonce()
        XCTAssertEqual(podState.currentNonce, 0x15022c8a)
        podState.advanceToNextNonce()
        XCTAssertEqual(podState.currentNonce, 0xacf076ca)
    }
    
    func testResyncNonce() {
        do {
            let config = try VersionResponse(encodedData: Data(hexadecimalString: "011502070002070002020000a62b0002249da11f00ee860318")!)
            var podState = PodState(address: config.address, pmVersion: config.firmwareVersion.description, piVersion: config.iFirmwareVersion.description, lot: config.lot, tid: config.tid, insulinType: .novolog)

            XCTAssertEqual(42539, config.lot)
            XCTAssertEqual(140445, config.tid)
            
            XCTAssertEqual(0x8fd39264, podState.currentNonce)

            // ID1:1f00ee86 PTYPE:PDM SEQ:26 ID2:1f00ee86 B9:24 BLEN:6 BODY:1c042e07c7c703c1 CRC:f4
            let sentPacket = try Packet(encodedData: Data(hexadecimalString: "1f00ee86ba1f00ee8624061c042e07c7c703c1f4")!)
            let sentMessage = try Message(encodedData: sentPacket.data)
            let sentCommand = sentMessage.messageBlocks[0] as! DeactivatePodCommand
            
            let errorResponse = try ErrorResponse(encodedData: Data(hexadecimalString: "06031492c482f5")!)

            XCTAssertEqual(9, sentMessage.sequenceNum)
            switch errorResponse.errorResponseType {
            case .badNonce(let nonceResyncKey):
                podState.resyncNonce(syncWord: nonceResyncKey, sentNonce: sentCommand.nonce, messageSequenceNum: sentMessage.sequenceNum)
                XCTAssertEqual(0x40ccdacb, podState.currentNonce)
                break
            default:
                XCTFail("Unexpected non bad nonce response")
                break
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

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

