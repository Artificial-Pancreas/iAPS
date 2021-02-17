//
//  BolusTests.swift
//  OmniKitTests
//
//  Created by Eelke Jager on 04/09/2018.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

import XCTest
@testable import OmniKit

class BolusTests: XCTestCase {
        func testSetBolusCommand() {
        //    2017-09-11T11:07:57.476872 ID1:1f08ced2 PTYPE:PDM SEQ:18 ID2:1f08ced2 B9:18 BLEN:31 MTYPE:1a0e BODY:bed2e16b02010a0101a000340034170d000208000186a0 CRC:fd
        //    2017-09-11T11:07:57.552574 ID1:1f08ced2 PTYPE:ACK SEQ:19 ID2:1f08ced2 CRC:b8
        //    2017-09-11T11:07:57.734557 ID1:1f08ced2 PTYPE:CON SEQ:20 CON:00000000000003c0 CRC:a9
        
        do {
            // Decode
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0ebed2e16b02010a0101a000340034")!)
            XCTAssertEqual(0xbed2e16b, cmd.nonce)
            
            if case SetInsulinScheduleCommand.DeliverySchedule.bolus(let units, let timeBetweenPulses) = cmd.deliverySchedule {
                XCTAssertEqual(2.6, units)
                XCTAssertEqual(.seconds(1), timeBetweenPulses)
            } else {
                XCTFail("Expected ScheduleEntry.bolus type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let timeBetweenPulses = TimeInterval(seconds: 1)
        let scheduleEntry = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: 2.6, timeBetweenPulses: timeBetweenPulses)
        let cmd = SetInsulinScheduleCommand(nonce: 0xbed2e16b, deliverySchedule: scheduleEntry)
        XCTAssertEqual("1a0ebed2e16b02010a0101a000340034", cmd.data.hexadecimalString)
    }

    func testBolusExtraCommand() {
        // 30U bolus
        // 17 0d 7c 1770 00030d40 000000000000

        do {
            // Decode
            let cmd = try BolusExtraCommand(encodedData: Data(hexadecimalString: "170d7c177000030d40000000000000")!)
            XCTAssertEqual(30.0, cmd.units)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(true, cmd.completionBeep)
            XCTAssertEqual(.hours(1), cmd.programReminderInterval)
            XCTAssertEqual(.seconds(2), cmd.timeBetweenPulses)
            XCTAssertEqual(0, cmd.squareWaveUnits)
            XCTAssertEqual(0, cmd.squareWaveDuration)
            
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode typical prime
        let cmd = BolusExtraCommand(units: 2.6, timeBetweenPulses: .seconds(1))
        XCTAssertEqual("170d000208000186a0000000000000", cmd.data.hexadecimalString)
    }
    
    func testBolusExtraOddPulseCount() {
        // 17 0d 7c 00fa 00030d40 000000000000
        let cmd = BolusExtraCommand(units: 1.25, acknowledgementBeep: false, completionBeep: true, programReminderInterval: .hours(1))
        XCTAssertEqual("170d7c00fa00030d40000000000000", cmd.data.hexadecimalString)
    }

    //    1a 0e NNNNNNNN 02 CCCC HH SSSS 0ppp 0ppp 17 LL RR NNNN XXXXXXXX
    //    1a 0e 19e4890b 02 0025 01 0020 0002 0002 17 0d 00 001e 00030d40
    //    0ppp = $0002                     -> 2 pulses
    //    NNNN = $001e = 30 (dec) / 10     -> 3 pulses
    

    // Found in PDM logs: 1a0e243085c802002501002000020002 170d00001400030d40000000000000
    func testBolusAndBolusExtraMatch() {
        let bolusAmount = 0.1
        
        // 1a 0e NNNNNNNN 02 CCCC HH SSSS 0ppp 0ppp
        // 1a 0e 243085c8 02 0025 01 0020 0002 0002
        let timeBetweenPulses = TimeInterval(seconds: 2)
        let scheduleEntry = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: bolusAmount, timeBetweenPulses: timeBetweenPulses)
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0x243085c8, deliverySchedule: scheduleEntry)
        XCTAssertEqual("1a0e243085c802002501002000020002", bolusCommand.data.hexadecimalString)

        // 17 LL RR NNNN XXXXXXXX
        // 17 0d 00 0014 00030d40 000000000000
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount)
        XCTAssertEqual("170d00001400030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }

    func testBolusAndBolusExtraMatch2() {
        let bolusAmount = 0.15
        let timeBetweenPulses = TimeInterval(seconds: 2)
        let scheduleEntry = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: bolusAmount, timeBetweenPulses: timeBetweenPulses)
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0x243085c8, deliverySchedule: scheduleEntry)
        XCTAssertEqual("1a0e243085c802003701003000030003", bolusCommand.data.hexadecimalString)
        
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount)
        XCTAssertEqual("170d00001e00030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }
    
    func testLargeBolus() {
        let bolusAmount = 29.95
        let timeBetweenPulses = TimeInterval(seconds: 2)
        let scheduleEntry = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: bolusAmount, timeBetweenPulses: timeBetweenPulses)
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0x31204ba7, deliverySchedule: scheduleEntry)
        XCTAssertEqual("1a0e31204ba702014801257002570257", bolusCommand.data.hexadecimalString)
        
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount, acknowledgementBeep: false, completionBeep: true, programReminderInterval: .hours(1))
        XCTAssertEqual("170d7c176600030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }
    
    func testOddBolus() {
        // 1a 0e NNNNNNNN 02 CCCC HH SSSS 0ppp 0ppp
        // 1a 0e cf9e81ac 02 00e5 01 0290 0029 0029

        let bolusAmount = 2.05
        let timeBetweenPulses = TimeInterval(seconds: 2)
        let scheduleEntry = SetInsulinScheduleCommand.DeliverySchedule.bolus(units: bolusAmount, timeBetweenPulses: timeBetweenPulses)
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0xcf9e81ac, deliverySchedule: scheduleEntry)
        XCTAssertEqual("1a0ecf9e81ac0200e501029000290029", bolusCommand.data.hexadecimalString)
        
        // 17 LL RR NNNN XXXXXXXX
        // 17 0d 3c 019a 00030d40 0000 00000000
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount, acknowledgementBeep: false, completionBeep: false, programReminderInterval: .hours(1))
        XCTAssertEqual("170d3c019a00030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }

    
    func testCancelBolusCommand() {
        do {
            // Decode 1f 05 4d91f8ff 64
            let cmd = try CancelDeliveryCommand(encodedData: Data(hexadecimalString: "1f054d91f8ff64")!)
            XCTAssertEqual(0x4d91f8ff, cmd.nonce)
            XCTAssertEqual(.beeeeeep, cmd.beepType)
            XCTAssertEqual(.bolus, cmd.deliveryType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = CancelDeliveryCommand(nonce: 0x4d91f8ff, deliveryType: .bolus, beepType: .beeeeeep)
        XCTAssertEqual("1f054d91f8ff64", cmd.data.hexadecimalString)
    }
}
