//
//  MySentryPumpStatusMessageBodyTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/6/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import MinimedKit

class MySentryPumpStatusMessageBodyTests: XCTestCase {
        
    func testValidPumpStatusMessage() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a2594040042f511727070f09050184850000cd010105b03e0a0a1a009d030000711726000f09050000")!)
        
        if let message = message {
            XCTAssertTrue(message.messageBody is MySentryPumpStatusMessageBody)
        } else {
            XCTFail("\(String(describing: message)) is nil")
        }
    }
    
    func testGlucoseTrendFlat() {
        XCTAssertEqual(GlucoseTrend.flat, GlucoseTrend(byte: 0b00000000))
        XCTAssertEqual(GlucoseTrend.flat, GlucoseTrend(byte: 0b11110001))
        XCTAssertEqual(GlucoseTrend.flat, GlucoseTrend(byte: 0b11110001))
        XCTAssertEqual(GlucoseTrend.flat, GlucoseTrend(byte: 0b000))
        XCTAssertEqual(GlucoseTrend.flat, GlucoseTrend(byte: 0x51))
    }
    
    func testMidnightSensor() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a2594040049c510003310f090501393700025b0101068d262208150034000000700003000f09050000")!)!
        
        let body = message.messageBody as! MySentryPumpStatusMessageBody
        
        switch body.glucose {
        case .active(glucose: let glucose):
            XCTAssertEqual(114, glucose)
        default:
            XCTFail("\(body.glucose) is not .Active")
        }
        
        switch body.previousGlucose {
        case .active(glucose: let glucose):
            XCTAssertEqual(110, glucose)
        default:
            XCTFail("\(body.previousGlucose) is not .Active")
        }
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 5
        dateComponents.hour = 0
        dateComponents.minute = 3
        dateComponents.second = 49
        
        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        
        dateComponents.second = 0
        
        XCTAssertEqual(dateComponents, body.glucoseDateComponents)
        
        XCTAssertEqual(GlucoseTrend.flat, body.glucoseTrend)
    }
    
    func testActiveSensor() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a2594040042f511727070f09050184850000cd010105b03e0a0a1a009d030000711726000f09050000")!)!
        
        let body = message.messageBody as! MySentryPumpStatusMessageBody
        
        switch body.glucose {
        case .active(glucose: let glucose):
            XCTAssertEqual(265, glucose)
        default:
            XCTFail("\(body.glucose) is not .Active")
        }
        
        switch body.previousGlucose {
        case .active(glucose: let glucose):
            XCTAssertEqual(267, glucose)
        default:
            XCTFail("\(body.previousGlucose) is not .Active")
        }
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 5
        dateComponents.hour = 23
        dateComponents.minute = 39
        dateComponents.second = 7
        
        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        
        dateComponents.minute = 38
        dateComponents.second = 0
        
        XCTAssertEqual(dateComponents, body.glucoseDateComponents)
        
        XCTAssertEqual(GlucoseTrend.flat, body.glucoseTrend)
    }
    
    func testSensorEndEmptyReservoir() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a259404004fb511205000f090601050502000004000000ff00ffff0040000000711205000f09060000")!)!
        
        let body = message.messageBody as! MySentryPumpStatusMessageBody
        
        switch body.glucose {
        case .ended:
            break
        default:
            XCTFail("\(body.glucose) is not .Ended")
        }
        
        switch body.previousGlucose {
        case .ended:
            break
        default:
            XCTFail("\(body.previousGlucose) is not .Ended")
        }
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 6
        dateComponents.hour = 18
        dateComponents.minute = 5
        dateComponents.second = 0
        
        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        XCTAssertEqual(dateComponents, body.glucoseDateComponents)
        
        XCTAssertEqual(GlucoseTrend.flat, body.glucoseTrend)
    }
    
    func testSensorOffEmptyReservoir() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a259404004ff501219000f09060100000000000400000000000000005e000000720000000000000000")!)!
        
        let body = message.messageBody as! MySentryPumpStatusMessageBody
        
        switch body.glucose {
        case .off:
            break
        default:
            XCTFail("\(body.glucose) is not .Off")
        }
        
        switch body.previousGlucose {
        case .off:
            break
        default:
            XCTFail("\(body.previousGlucose) is not .Off")
        }
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 6
        dateComponents.hour = 18
        dateComponents.minute = 25
        dateComponents.second = 0
        
        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        XCTAssertNil(body.glucoseDateComponents)
        
        XCTAssertEqual(GlucoseTrend.flat, body.glucoseTrend)
    }
    
    func testSensorOffEmptyReservoirSuspended() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a25940400401501223000f090601000000000004000000000000000059000000720000000000000000")!)!
        
        let body = message.messageBody as! MySentryPumpStatusMessageBody
        
        switch body.glucose {
        case .off:
            break
        default:
            XCTFail("\(body.glucose) is not .Off")
        }
        
        switch body.previousGlucose {
        case .off:
            break
        default:
            XCTFail("\(body.previousGlucose) is not .Off")
        }
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year = 2015
        dateComponents.month = 9
        dateComponents.day = 6
        dateComponents.hour = 18
        dateComponents.minute = 35
        dateComponents.second = 0
        
        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        XCTAssertNil(body.glucoseDateComponents)
        
        XCTAssertEqual(GlucoseTrend.flat, body.glucoseTrend)
    }
 
    func testClockType24Hour() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a295099004b6d5971f1510070a013f3a0002dd020105bd08880825000502000755171e0010070a0000")!)!
        
        let body = message.messageBody as! MySentryPumpStatusMessageBody
        
        var dateComponents = DateComponents()
        dateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        dateComponents.year = 2016
        dateComponents.month = 7
        dateComponents.day = 10
        dateComponents.hour = 23
        dateComponents.minute = 31
        dateComponents.second = 21
        
        XCTAssertEqual(dateComponents, body.pumpDateComponents)
        
        var glucoseDateComponents = DateComponents()
        glucoseDateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        glucoseDateComponents.year = 2016
        glucoseDateComponents.month = 7
        glucoseDateComponents.day = 10
        glucoseDateComponents.hour = 23
        glucoseDateComponents.minute = 30
        glucoseDateComponents.second = 0

        XCTAssertEqual(glucoseDateComponents, body.glucoseDateComponents)
        
        XCTAssertEqual(ClockType.twentyFourHour, body.clockType)
    }
   
}
