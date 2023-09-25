//
//  StatusTests.swift
//  OmniBLE
//
//  Created by Eelke Jager on 08/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//  From OmniKitTests/StatusTests.swift
//
import Foundation

import XCTest
@testable import OmniBLE

class StatusTests: XCTestCase {
    
    func testStatusRequestCommand() {
        // 0e 01 00
        do {
            // Encode
            let encoded = GetStatusCommand(podInfoType: .normal)
            XCTAssertEqual("0e0100", encoded.data.hexadecimalString)
            
            // Decode
            let decoded = try GetStatusCommand(encodedData: Data(hexadecimalString: "0e0100")!)
            XCTAssertEqual(.normal, decoded.podInfoType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testStatusResponse46UnitsLeft() {
        /// 1d19050ec82c08376f9801dc
        do {
            // Decode
            let decoded = try StatusResponse(encodedData: Data(hexadecimalString: "1d19050ec82c08376f9801dc")!)
            XCTAssertEqual(TimeInterval(minutes: 3547), decoded.timeActive)
            XCTAssertEqual(.scheduledBasal, decoded.deliveryStatus)
            XCTAssertEqual(.fiftyOrLessUnits, decoded.podProgressStatus)
            XCTAssertEqual(129.45, decoded.insulinDelivered, accuracy: 0.01)
            XCTAssertEqual(46.00, decoded.reservoirLevel)
            XCTAssertEqual(2.2, decoded.bolusNotDelivered)
            XCTAssertEqual(9, decoded.lastProgrammingMessageSeqNum)
            //XCTAssert(,decoded.alarms)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testStatusRequestCommandConfiguredAlerts() {
        // 0e 01 01
        do {
            // Encode
            let encoded = GetStatusCommand(podInfoType: .configuredAlerts)
            XCTAssertEqual("0e0101", encoded.data.hexadecimalString)
                
            // Decode
            let decoded = try GetStatusCommand(encodedData: Data(hexadecimalString: "0e0101")!)
            XCTAssertEqual(.configuredAlerts, decoded.podInfoType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
    
    func testStatusRequestCommandFaultEvents() {
        // 0e 01 02
        do {
            // Encode
            let encoded = GetStatusCommand(podInfoType: .detailedStatus)
            XCTAssertEqual("0e0102", encoded.data.hexadecimalString)
            
            // Decode
            let decoded = try GetStatusCommand(encodedData: Data(hexadecimalString: "0e0102")!)
            XCTAssertEqual(.detailedStatus, decoded.podInfoType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }
}
