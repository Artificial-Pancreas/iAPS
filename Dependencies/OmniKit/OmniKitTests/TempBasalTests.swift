//
//  TempBasalTests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 6/5/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import Foundation

import XCTest
@testable import OmniKit

class TempBasalTests: XCTestCase {
    
    func testRateQuantization() {
//        // Test previously failing case
//        XCTAssertEqual(0.15, OmnipodPumpManager.roundToDeliveryIncrement(units: 0.15))
//        
//        XCTAssertEqual(0.15, OmnipodPumpManager.roundToDeliveryIncrement(units: 0.15000000000000002))
//        
//        XCTAssertEqual(0.15, OmnipodPumpManager.roundToDeliveryIncrement(units: 0.145))
    }
    
    func testAlternatingSegmentFlag() {
        // Encode 0.05U/hr 30mins
        let cmd = SetInsulinScheduleCommand(nonce: 0x9746c65b, tempBasalRate: 0.05, duration: .hours(0.5))
        // 1a 0e 9746c65b 01 0079 01 3840 0000 0000
        XCTAssertEqual("1a0e9746c65b01007901384000000000", cmd.data.hexadecimalString)

        // Encode 0.05U/hr 8.5hours
        let cmd2 = SetInsulinScheduleCommand(nonce: 0x9746c65b, tempBasalRate: 0.05, duration: .hours(8.5))
        // 1a 10 9746c65b 01 0091 11 3840 0000 f800 0000
        XCTAssertEqual("1a109746c65b0100911138400000f8000000", cmd2.data.hexadecimalString)
        
        // Encode 0.05U/hr 16.5hours
        let cmd3 = SetInsulinScheduleCommand(nonce: 0x9746c65b, tempBasalRate: 0.05, duration: .hours(16.5))
        // 1a 12 9746c65b 01 00a9 21 3840 0000 f800 f800 0000
        XCTAssertEqual("1a129746c65b0100a92138400000f800f8000000", cmd3.data.hexadecimalString)
    }
    
    func testTempBasalThreeTenthsUnitPerHour() {
        let cmd = SetInsulinScheduleCommand(nonce: 0xeac79411, tempBasalRate: 0.3, duration: .hours(0.5))
        XCTAssertEqual("1a0eeac7941101007f01384000030003", cmd.data.hexadecimalString)
    }
    
    func testSetTempBasalCommand() {
        do {
            // Decode 1a 0e ea2d0a3b 01 007d 01 3840 0002 0002
            //        1a 0e 9746c65b 01 0079 01 3840 0000 0000 160e7c00000515752a
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0eea2d0a3b01007d01384000020002")!)

            XCTAssertEqual(0xea2d0a3b, cmd.nonce)
            if case SetInsulinScheduleCommand.DeliverySchedule.tempBasal(let secondsRemaining, let firstSegmentPulses, let table) = cmd.deliverySchedule {
                
                XCTAssertEqual(1800, secondsRemaining)
                XCTAssertEqual(2, firstSegmentPulses)
                let entry = table.entries[0]
                XCTAssertEqual(1, entry.segments)
                XCTAssertEqual(2, entry.pulses)
            } else {
                XCTFail("Expected ScheduleEntry.tempBasal type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }

        // Encode
        let cmd = SetInsulinScheduleCommand(nonce: 0xea2d0a3b, tempBasalRate: 0.20, duration: .hours(0.5))
        XCTAssertEqual("1a0eea2d0a3b01007d01384000020002", cmd.data.hexadecimalString)
    }
    
    func testSetTempBasalWithAlternatingPulse() {
        do {
            // 0.05U/hr for 2.5 hours
            // Decode 1a 0e 4e2c2717 01 007f 05 3840 0000 4800
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0e4e2c271701007f05384000004800")!)
            
            XCTAssertEqual(0x4e2c2717, cmd.nonce)
            if case SetInsulinScheduleCommand.DeliverySchedule.tempBasal(let secondsRemaining, let firstSegmentPulses, let table) = cmd.deliverySchedule {
                
                XCTAssertEqual(1800, secondsRemaining)
                XCTAssertEqual(0, firstSegmentPulses)
                XCTAssertEqual(1, table.entries.count)
                XCTAssertEqual(5, table.entries[0].segments)
                XCTAssertEqual(0, table.entries[0].pulses)
                XCTAssertEqual(true, table.entries[0].alternateSegmentPulse)
            } else {
                XCTFail("Expected ScheduleEntry.tempBasal type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = SetInsulinScheduleCommand(nonce: 0x4e2c2717, tempBasalRate: 0.05, duration: .hours(2.5))
        XCTAssertEqual("1a0e4e2c271701007f05384000004800", cmd.data.hexadecimalString)
    }

    func testLargerTempBasalCommand() {
        do {
            // 2.00 U/h for 1.5h
            // Decode 1a 0e 87e8d03a 01 00cb 03 3840 0014 2014
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0e87e8d03a0100cb03384000142014")!)
            
            XCTAssertEqual(0x87e8d03a, cmd.nonce)
            if case SetInsulinScheduleCommand.DeliverySchedule.tempBasal(let secondsRemaining, let firstSegmentPulses, let table) = cmd.deliverySchedule {
                
                XCTAssertEqual(1800, secondsRemaining)
                XCTAssertEqual(0x14, firstSegmentPulses)
                let entry = table.entries[0]
                XCTAssertEqual(3, entry.segments)
                XCTAssertEqual(20, entry.pulses)
            } else {
                XCTFail("Expected ScheduleEntry.tempBasal type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = SetInsulinScheduleCommand(nonce: 0x87e8d03a, tempBasalRate: 2, duration: .hours(1.5))
        XCTAssertEqual("1a0e87e8d03a0100cb03384000142014", cmd.data.hexadecimalString)
    }

    func testCancelTempBasalCommand() {
        do {
            // Decode 1f 05 f76d34c4 62
            let cmd = try CancelDeliveryCommand(encodedData: Data(hexadecimalString: "1f05f76d34c462")!)
            XCTAssertEqual(0xf76d34c4, cmd.nonce)
            XCTAssertEqual(.beeeeeep, cmd.beepType)
            XCTAssertEqual(.tempBasal, cmd.deliveryType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = CancelDeliveryCommand(nonce: 0xf76d34c4, deliveryType: .tempBasal, beepType: .beeeeeep)
        XCTAssertEqual("1f05f76d34c462", cmd.data.hexadecimalString)
    }
    
    func testCancelTempBasalnoBeepCommand() {
        do {
            let cmd = try CancelDeliveryCommand(encodedData: Data(hexadecimalString: "1f05f76d34c402")!)
            XCTAssertEqual(0xf76d34c4, cmd.nonce)
            XCTAssertEqual(.noBeepCancel, cmd.beepType)
            XCTAssertEqual(.tempBasal, cmd.deliveryType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = CancelDeliveryCommand(nonce: 0xf76d34c4, deliveryType: .tempBasal, beepType: .noBeepCancel)
        XCTAssertEqual("1f05f76d34c402", cmd.data.hexadecimalString)
    }
    
    func testZeroTempExtraCommand() {
        do {
            // 0 U/h for 0.5 hours
            //        16 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ
            // Decode 16 0e 7c 00 0000 6b49d200 0000 6b49d200

            let cmd = try TempBasalExtraCommand(encodedData: Data(hexadecimalString: "160e7c0000006b49d20000006b49d200")!)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(true, cmd.completionBeep)
            XCTAssertEqual(.minutes(60), cmd.programReminderInterval)
            XCTAssertEqual(TimeInterval(hours: 5), cmd.delayUntilFirstPulse)
            XCTAssertEqual(0, cmd.remainingPulses)
            XCTAssertEqual(1, cmd.rateEntries.count)
            let entry = cmd.rateEntries[0]
            XCTAssertEqual(TimeInterval(hours: 5), entry.delayBetweenPulses)
            XCTAssertEqual(TimeInterval(minutes: 30), entry.duration)
            XCTAssertEqual(0, entry.rate)
            
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = TempBasalExtraCommand(rate: 0, duration: .hours(0.5), acknowledgementBeep: false, completionBeep: true, programReminderInterval: .minutes(60))
        XCTAssertEqual("160e7c0000006b49d20000006b49d200", cmd.data.hexadecimalString)
    }
    
    func testZeroTempThreeHoursExtraCommand() {
        do {
            // 0 U/h for 3 hours
            let cmd = try TempBasalExtraCommand(encodedData: Data(hexadecimalString: "162c7c0000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d200")!)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(true, cmd.completionBeep)
            XCTAssertEqual(.minutes(60), cmd.programReminderInterval)
            XCTAssertEqual(TimeInterval(hours: 5), cmd.delayUntilFirstPulse)
            XCTAssertEqual(0, cmd.remainingPulses)
            XCTAssertEqual(6, cmd.rateEntries.count)
            for entry in cmd.rateEntries {
                XCTAssertEqual(TimeInterval(hours: 5), entry.delayBetweenPulses)
                XCTAssertEqual(TimeInterval(minutes: 30), entry.duration)
                XCTAssertEqual(0, entry.rate)
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = TempBasalExtraCommand(rate: 0, duration: .hours(3), acknowledgementBeep: false, completionBeep: true, programReminderInterval: .minutes(60))
        XCTAssertEqual("162c7c0000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d200", cmd.data.hexadecimalString)
    }

    func testZeroTempTwelveHoursExtraCommand() {
        do {
            // 0 U/h for 12 hours
            //        16 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
            //        16 98 7c 00 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200 0000 6b49d200
            let cmd = try TempBasalExtraCommand(encodedData: Data(hexadecimalString: "16987c0000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d200")!)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(true, cmd.completionBeep)
            XCTAssertEqual(.minutes(60), cmd.programReminderInterval)
            XCTAssertEqual(TimeInterval(hours: 5), cmd.delayUntilFirstPulse)
            XCTAssertEqual(0, cmd.remainingPulses)
            XCTAssertEqual(24, cmd.rateEntries.count)
            for entry in cmd.rateEntries {
                XCTAssertEqual(0, entry.totalPulses)
                XCTAssertEqual(TimeInterval(hours: 5), entry.delayBetweenPulses)
                XCTAssertEqual(TimeInterval(minutes: 30), entry.duration)
                XCTAssertEqual(0, entry.rate)
            }

        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }

        // Encode
        let cmd = TempBasalExtraCommand(rate: 0, duration: .hours(12), acknowledgementBeep: false, completionBeep: true, programReminderInterval: .minutes(60))
        XCTAssertEqual("16987c0000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d20000006b49d200", cmd.data.hexadecimalString)
    }

    func testTempBasalExtremeValues() {
        do {
            // 30 U/h for 12 hours
            // Decode 1a 10 a958c5ad 01 04f5 18 3840 012c f12c 712c
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a10a958c5ad0104f5183840012cf12c712c")!)
            
            XCTAssertEqual(0xa958c5ad, cmd.nonce)
            if case SetInsulinScheduleCommand.DeliverySchedule.tempBasal(let secondsRemaining, let firstSegmentPulses, let table) = cmd.deliverySchedule {
                
                XCTAssertEqual(1800, secondsRemaining)
                XCTAssertEqual(300, firstSegmentPulses)
                XCTAssertEqual(2, table.entries.count)
                let entry1 = table.entries[0]
                XCTAssertEqual(16, entry1.segments)
                XCTAssertEqual(300, entry1.pulses)
                let entry2 = table.entries[1]
                XCTAssertEqual(8, entry2.segments)
                XCTAssertEqual(300, entry2.pulses)
            } else {
                XCTFail("Expected ScheduleEntry.tempBasal type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = SetInsulinScheduleCommand(nonce: 0xa958c5ad, tempBasalRate: 30, duration: .hours(12))
        XCTAssertEqual("1a10a958c5ad0104f5183840012cf12c712c", cmd.data.hexadecimalString)
    }

    func testTempBasalExtraCommand() {
        do {
            // 30 U/h for 0.5 hours
            // Decode 16 0e 7c 00 0bb8 000927c0 0bb8 000927c0
            let cmd = try TempBasalExtraCommand(encodedData: Data(hexadecimalString: "160e7c000bb8000927c00bb8000927c0")!)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(true, cmd.completionBeep)
            XCTAssertEqual(.minutes(60), cmd.programReminderInterval)
            XCTAssertEqual(TimeInterval(seconds: 6), cmd.delayUntilFirstPulse)
            XCTAssertEqual(300, cmd.remainingPulses)
            XCTAssertEqual(1, cmd.rateEntries.count)
            let entry = cmd.rateEntries[0]
            XCTAssertEqual(TimeInterval(seconds: 6), entry.delayBetweenPulses)
            XCTAssertEqual(TimeInterval(minutes: 30), entry.duration)
            XCTAssertEqual(30, entry.rate)

        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = TempBasalExtraCommand(rate: 30, duration: .hours(0.5), acknowledgementBeep: false, completionBeep: true, programReminderInterval: .minutes(60))
        XCTAssertEqual("160e7c000bb8000927c00bb8000927c0", cmd.data.hexadecimalString)
    }
    
    func testBasalExtraCommandForOddPulseCountRate() {

        let cmd1 = TempBasalExtraCommand(rate: 0.05, duration: .hours(0.5), acknowledgementBeep: false, completionBeep: true, programReminderInterval: .minutes(60))
        XCTAssertEqual("160e7c00000515752a00000515752a00", cmd1.data.hexadecimalString)
        
        let cmd2 = TempBasalExtraCommand(rate: 2.05, duration: .hours(0.5), acknowledgementBeep: false, completionBeep: false, programReminderInterval: .minutes(60))
        XCTAssertEqual("160e3c0000cd0085fac700cd0085fac7", cmd2.data.hexadecimalString)

        let cmd3 = TempBasalExtraCommand(rate: 2.10, duration: .hours(0.5), acknowledgementBeep: false, completionBeep: false, programReminderInterval: .minutes(60))
        XCTAssertEqual("160e3c0000d20082ca2400d20082ca24", cmd3.data.hexadecimalString)

        let cmd4 = TempBasalExtraCommand(rate: 2.15, duration: .hours(0.5), acknowledgementBeep: false, completionBeep: false, programReminderInterval: .minutes(60))
        XCTAssertEqual("160e3c0000d7007fbf7d00d7007fbf7d", cmd4.data.hexadecimalString)
    }
    
    func testBasalExtraCommandPulseCount() {
        // 16 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // 16 14 00 00 f5b9 000a0ad7 f5b9 000a0ad7 0aaf 000a0ad7
        // 16 14 00 00 f618 000a0ad7 f618 000a0ad7 0a50 000a0ad7
        let cmd2 = TempBasalExtraCommand(rate: 27.35, duration: .hours(12), acknowledgementBeep: false, completionBeep: false, programReminderInterval: 0)
        XCTAssertEqual("16140000f5b9000a0ad7f5b9000a0ad70aaf000a0ad7", cmd2.data.hexadecimalString)
    }

    func testTempBasalExtraCommandExtremeValues() {
        do {
            // 30 U/h for 12 hours
            // Decode 16 14 3c 00 f618 000927c0 f618 000927c0 2328 000927c0
            let cmd = try TempBasalExtraCommand(encodedData: Data(hexadecimalString: "16143c00f618000927c0f618000927c02328000927c0")!)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(false, cmd.completionBeep)
            XCTAssertEqual(.minutes(60), cmd.programReminderInterval)
            XCTAssertEqual(TimeInterval(seconds: 6), cmd.delayUntilFirstPulse)
            XCTAssertEqual(6300, cmd.remainingPulses)
            XCTAssertEqual(2, cmd.rateEntries.count)
            let entry = cmd.rateEntries[0]
            XCTAssertEqual(TimeInterval(seconds: 6), entry.delayBetweenPulses)
            XCTAssertEqual(TimeInterval(hours: 10.5), entry.duration)
            XCTAssertEqual(30, entry.rate)
            
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = TempBasalExtraCommand(rate: 30, duration: .hours(12), acknowledgementBeep: false, completionBeep: false, programReminderInterval: .minutes(60))
        XCTAssertEqual("16143c00f618000927c0f618000927c02328000927c0", cmd.data.hexadecimalString)
    }
    
    func testTempBasalExtraCommandExtremeValues2() {
        do {
            // 29.95 U/h for 12 hours
            let cmd = try TempBasalExtraCommand(encodedData: Data(hexadecimalString: "16143c00f5af00092ba9f5af00092ba9231900092ba9")!)
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(false, cmd.completionBeep)
            XCTAssertEqual(.minutes(60), cmd.programReminderInterval)
            XCTAssertEqual(TimeInterval(seconds: 6.01001), cmd.delayUntilFirstPulse)
            XCTAssertEqual(6289.5, cmd.remainingPulses)
            XCTAssertEqual(2, cmd.rateEntries.count)
            let entry1 = cmd.rateEntries[0]
            let entry2 = cmd.rateEntries[1]
            XCTAssertEqual(TimeInterval(seconds: 6.01001), entry1.delayBetweenPulses, accuracy: .ulpOfOne)
            XCTAssertEqual(TimeInterval(hours: 12), entry1.duration + entry2.duration, accuracy: 1)
            XCTAssertEqual(29.95, entry1.rate, accuracy: 0.025)
            
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        let cmd = TempBasalExtraCommand(rate: 29.95, duration: .hours(12), acknowledgementBeep: false, completionBeep: false, programReminderInterval: .minutes(60))
        XCTAssertEqual("16143c00f5af00092ba9f5af00092ba9231900092ba9", cmd.data.hexadecimalString)
    }
}
