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
    func testPrimeBolusCommand() {
        //    2017-09-11T11:07:57.476872 ID1:1f08ced2 PTYPE:PDM SEQ:18 ID2:1f08ced2 B9:18 BLEN:31 MTYPE:1a0e BODY:bed2e16b02010a0101a000340034170d000208000186a0 CRC:fd
        //    2017-09-11T11:07:57.552574 ID1:1f08ced2 PTYPE:ACK SEQ:19 ID2:1f08ced2 CRC:b8
        //    2017-09-11T11:07:57.734557 ID1:1f08ced2 PTYPE:CON SEQ:20 CON:00000000000003c0 CRC:a9
        
        do {
            // Decode
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp
            // 1a 0e bed2e16b 02 010a 01 01a0 0034 0034
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a0ebed2e16b02010a0101a000340034")!)
            XCTAssertEqual(0xbed2e16b, cmd.nonce)
            
            if case SetInsulinScheduleCommand.DeliverySchedule.bolus(let units, let timeBetweenPulses, let table) = cmd.deliverySchedule {
                XCTAssertEqual(Pod.primeUnits, units)
                XCTAssertEqual(Pod.secondsPerPrimePulse, timeBetweenPulses)
                XCTAssertEqual(1, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(Int(Pod.primeUnits / Pod.pulseSize), table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
            } else {
                XCTFail("Expected ScheduleEntry.bolus type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = SetInsulinScheduleCommand(nonce: 0xbed2e16b, units: Pod.primeUnits, timeBetweenPulses: Pod.secondsPerPrimePulse)
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
            XCTAssertEqual(Pod.secondsPerBolusPulse, cmd.timeBetweenPulses)
            XCTAssertEqual(0, cmd.extendedUnits)
            XCTAssertEqual(0, cmd.extendedDuration)
            
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode typical prime
        let cmd = BolusExtraCommand(units: Pod.primeUnits, timeBetweenPulses: Pod.secondsPerPrimePulse)
        XCTAssertEqual("170d000208000186a0000000000000", cmd.data.hexadecimalString)
    }

    func testExtendedBolus() {
        // 1.0U extended (square wave) bolus over 1 hour with no immediate bolus
        // 1A LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
        // 1a 10 0375a602 02 0017 03 0000 0000 0000 100a
        do {
            let insulinCmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a100375a60202001703000000000000100a")!)
            XCTAssertEqual(0x0375a602, insulinCmd.nonce)
            let schedule = insulinCmd.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(0.0, units)
                XCTAssertEqual(0, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(0, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[1].segments)
                XCTAssertEqual(10, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }
        } catch (let error) {
            XCTFail("insulin command decoding threw error: \(error)")
        }

        // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 17 0d 7c 0000 00030d40 00c8 0112a880
        do {
            let extraCmd = try BolusExtraCommand(encodedData: Data(hexadecimalString: "170d7c000000030d4000c80112a880")!)
            XCTAssertEqual(false, extraCmd.acknowledgementBeep)
            XCTAssertEqual(true, extraCmd.completionBeep)
            XCTAssertEqual(.minutes(60), extraCmd.programReminderInterval)
            XCTAssertEqual(0.0, extraCmd.units)
            XCTAssertEqual(Pod.secondsPerBolusPulse, extraCmd.timeBetweenPulses)
            XCTAssertEqual(1.0, extraCmd.extendedUnits)
            XCTAssertEqual(.hours(1), extraCmd.extendedDuration)
        } catch (let error) {
            XCTFail("bolus extra command decoding threw error: \(error)")
        }
    }

    func testNoImmediateExtendedBolusDeliveryEncoding() {
        // 1.0U extended bolus over 4.5 hours
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp napp napp napp napp
        // 1a 16 b93c64f6 02 001e 0a 0000 0000 0000 3002 0003 2002 0003
        let bolus_1_00U_Ext_4_5Hr = SetInsulinScheduleCommand(nonce: 0xb93c64f6, units: 0.0, extendedUnits: 1.0, extendedDuration: .hours(4.5))
        XCTAssertEqual("1a16b93c64f602001e0a0000000000003002000320020003", bolus_1_00U_Ext_4_5Hr.data.hexadecimalString)

        // 0.05U extended bolus over 0.5 hours -> only one entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp   17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 05181992 02 0003 02 0000 0000 1800   17 0d 00 0000 00030d40 000a 0aba9500
        let bolus_0_05U_Ext_0_5Hr = SetInsulinScheduleCommand(nonce: 0x05181992, units: 0.0, extendedUnits: 0.05, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a0e0518199202000302000000001800", bolus_0_05U_Ext_0_5Hr.data.hexadecimalString)

        // 0.10U extended bolus over 1 hour -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
        // 1a 10 06211961 02 0005 03 0000 0000 1800 0001
        let bolus_0_10U_Ext_1Hr = SetInsulinScheduleCommand(nonce: 0x06211961, units: 0.0, extendedUnits: 0.10, extendedDuration: .hours(1))
        XCTAssertEqual("1a1006211961020005030000000018000001", bolus_0_10U_Ext_1Hr.data.hexadecimalString)

        // 0.10U extended bolus over 1.5 hours
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp -> non-zero first entry
        // 1a 10 04111967 02 0006 04 0000 0000 1000 1001
        let bolus_0_10U_Ext_1_5Hr = SetInsulinScheduleCommand(nonce: 0x08121964, units: 0.0, extendedUnits: 0.10, extendedDuration: .hours(1.5))
        XCTAssertEqual("1a1008121964020006040000000010001001", bolus_0_10U_Ext_1_5Hr.data.hexadecimalString)

        // 0.10U extended bolus over 2 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp
        // 1a 12 07041776 02 0007 05 0000 0000 1000 0001 1800
        let bolus_0_10U_Ext_2Hr = SetInsulinScheduleCommand(nonce: 0x04111967, units: 0.0, extendedUnits: 0.10, extendedDuration: .hours(2))
        XCTAssertEqual("1a12041119670200070500000000100000011800", bolus_0_10U_Ext_2Hr.data.hexadecimalString)

        // 0.15U extended bolus over 1 hour -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
        // 1a 10 05181983 02 0006 03 0000 0000 1800 0002
        let bolus_0_15U_Ext_1Hr = SetInsulinScheduleCommand(nonce: 0x05181983, units: 0.0, extendedUnits: 0.15, extendedDuration: .hours(1))
        XCTAssertEqual("1a1005181983020006030000000018000002", bolus_0_15U_Ext_1Hr.data.hexadecimalString)

        // 0.35U extended bolus over 0.5 hours
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
        // 1a 10 06151215 02 0009 02 0000 0000 0000 0007
        let bolus_0_35U_Ext_0_5Hr = SetInsulinScheduleCommand(nonce: 0x06151215, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a1006151215020009020000000000000007", bolus_0_35U_Ext_0_5Hr.data.hexadecimalString)

        // 0.35U extended bolus over 4.5 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp
        // 1a 14 07211946 02 0011 0a 0000 0000 1000 2001 1800 2001
        let bolus_0_35U_Ext_4_5Hr = SetInsulinScheduleCommand(nonce: 0x07211946, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(4.5))
        XCTAssertEqual("1a14072119460200110a000000001000200118002001", bolus_0_35U_Ext_4_5Hr.data.hexadecimalString)

        // 0.35U extended bolus over 5.0 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp napp napp
        // 1a 18 03231932 02 0012 0b 0000 0000 1000 1001 1800 0001 1800 1001
        let bolus_0_35U_Ext_5_0Hr = SetInsulinScheduleCommand(nonce: 0x03231932, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(5.0))
        XCTAssertEqual("1a18032319320200120b00000000100010011800000118001001", bolus_0_35U_Ext_5_0Hr.data.hexadecimalString)

        // 0.35U extended bolus over 5.5 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp
        // 1a 1c 03011936 02 0013 0c 0000 0000 1000 0001 1800 0001 1800 0001 1800 0001
        let bolus_0_35U_Ext_5_5Hr = SetInsulinScheduleCommand(nonce: 0x03011936, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(5.5))
        XCTAssertEqual("1a1c030119360200130c0000000010000001180000011800000118000001", bolus_0_35U_Ext_5_5Hr.data.hexadecimalString)

        // 0.35U extended bolus over 6.0 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp napp napp
        // 1a 18 03231957 02 0014 0d 0000 0000 1000 0001 3800 0001 3800 0001
        let bolus_0_35U_Ext_6_0Hr = SetInsulinScheduleCommand(nonce: 0x03231957, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(6.0))
        XCTAssertEqual("1a18032319570200140d00000000100000013800000138000001", bolus_0_35U_Ext_6_0Hr.data.hexadecimalString)

        // 0.35U extended bolus over 6.5 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp
        // 1a 14 08151959 02 0015 0e 0000 0000 1000 0001 9800 0001
        let bolus_0_35U_Ext_6_5Hr = SetInsulinScheduleCommand(nonce: 0x08151959, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(6.5))
        XCTAssertEqual("1a14081519590200150e000000001000000198000001", bolus_0_35U_Ext_6_5Hr.data.hexadecimalString)

        // 0.35U extended bolus over 7.0 hours -> non-zero first entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp
        // 1a 12 12041962 02 0016 0f 0000 0000 1000 0001 b800
        let bolus_0_35U_Ext_7_0Hr = SetInsulinScheduleCommand(nonce: 0x12041962, units: 0.0, extendedUnits: 0.35, extendedDuration: .hours(7.0))
        XCTAssertEqual("1a12120419620200160f0000000010000001b800", bolus_0_35U_Ext_7_0Hr.data.hexadecimalString)
    }

    func testBolusDualWave() {
        // 6.0U dual wave bolus with 2.0U immediate and 4.0U extended over 3 hours
        // 1A LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp napp
        // 1a 16 01e475cb 02 0129 07 0280 0028 0028 100d 000e 100d 000e
        // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 17 0d 3c 0190 00030d40 0320 00cdfe60
        do {
            let insulinCmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a1601e475cb02012907028000280028100d000e100d000e")!)
            XCTAssertEqual(0x01e475cb, insulinCmd.nonce)
            let schedule = insulinCmd.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(2.0, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(5, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(0x28, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[1].segments)
                XCTAssertEqual(0xd, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[2].segments)
                XCTAssertEqual(0xe, table.entries[2].pulses)
                XCTAssertEqual(false, table.entries[2].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[3].segments)
                XCTAssertEqual(0xd, table.entries[3].pulses)
                XCTAssertEqual(false, table.entries[3].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[4].segments)
                XCTAssertEqual(0xe, table.entries[4].pulses)
                XCTAssertEqual(false, table.entries[4].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            let extraCmd = try BolusExtraCommand(encodedData: Data(hexadecimalString: "170d3c019000030d40032000cdfe60")!)
            XCTAssertEqual(2.0, extraCmd.units)
            XCTAssertEqual(false, extraCmd.acknowledgementBeep)
            XCTAssertEqual(false, extraCmd.completionBeep)
            XCTAssertEqual(.hours(1), extraCmd.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, extraCmd.timeBetweenPulses)
            XCTAssertEqual(4, extraCmd.extendedUnits)
            XCTAssertEqual(.hours(3), extraCmd.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }

        // Encode 0.10 combo bolus with 0.05U immediate, 0.05U over 30 minutes -> only one entry used!
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp
        // 1a 0e 06021986 02 0015 02 0010 0001 1001
        let bolusScheduleCommand = SetInsulinScheduleCommand(nonce: 0x06021986, units: 0.05, extendedUnits: 0.05, extendedDuration: .minutes(30))
        XCTAssertEqual("1a0e0602198602001502001000011001", bolusScheduleCommand.data.hexadecimalString)

        // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 17 0d 00 000a 00030d40 000a 0aba9500
        let cmd = BolusExtraCommand(units: 0.05, timeBetweenPulses: Pod.secondsPerBolusPulse, extendedUnits: 0.05, extendedDuration: .hours(0.5), programReminderInterval: .minutes(60))
        XCTAssertEqual("170d3c000a00030d40000a0aba9500", cmd.data.hexadecimalString)
    }

    func testLargeExtendedBolus() {
        // 12U extended (square wave) bolus over 6 hours with no immediate bolus
        // 1A LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
        // 1a 10 03171958 02 00fd 0d 0000 0000 0000 b014
        do {
            let insulinCmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a10031719580200fd0d000000000000b014")!)
            XCTAssertEqual(0x03171958, insulinCmd.nonce)
            let schedule = insulinCmd.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(0.0, units)
                XCTAssertEqual(0, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(0, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(12, table.entries[1].segments)
                XCTAssertEqual(0x14, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }
        } catch (let error) {
            XCTFail("insulin command decoding threw error: \(error)")
        }

        // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 17 0d 7c 0000 00030d40 0960 00895440
        do {
            let extraCmd = try BolusExtraCommand(encodedData: Data(hexadecimalString: "170d7c000000030d40096000895440")!)
            XCTAssertEqual(false, extraCmd.acknowledgementBeep)
            XCTAssertEqual(true, extraCmd.completionBeep)
            XCTAssertEqual(.minutes(60), extraCmd.programReminderInterval)
            XCTAssertEqual(0.0, extraCmd.units)
            XCTAssertEqual(Pod.secondsPerBolusPulse, extraCmd.timeBetweenPulses)
            XCTAssertEqual(12, extraCmd.extendedUnits)
            XCTAssertEqual(.hours(6), extraCmd.extendedDuration)
        } catch (let error) {
            XCTFail("bolus extra command decoding threw error: \(error)")
        }

        // Encode 12U extended (square wave) bolus over 6 hours with no immediate bolus
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
        // 1a 10 07041960 02 00fd 0d 0000 0000 0000 b014
        let bolusScheduleCommand = SetInsulinScheduleCommand(nonce: 0x07041960, units: 0.0, extendedUnits: 12, extendedDuration: .hours(6))
        XCTAssertEqual("1a10070419600200fd0d000000000000b014", bolusScheduleCommand.data.hexadecimalString)

        let extraCmd = BolusExtraCommand(extendedUnits: 12, extendedDuration: .hours(6), completionBeep: true, programReminderInterval: .minutes(60))
        XCTAssertEqual("170d7c000000030d40096000895440", extraCmd.data.hexadecimalString)
    }

    func testLargeBolusDualWave() {
        // 30U dual bolus 50% extended over 8 hours
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp    17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 1a 1e 11161988 02 0269 11 12c0 012c 012c 1812 1013 1812 1013 1812 1013 1812 1013    17 0d 7c 0bb8 00030d40 0bb8 00927c00
            let insulinCmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a1e111619880202691112c0012c012c18121013181210131812101318121013")!)
            XCTAssertEqual(0x11161988, insulinCmd.nonce)
            let schedule = insulinCmd.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(15.0, units)
                XCTAssertEqual(2, timeBetweenPulses)
                XCTAssertEqual(9, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(0x12c, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[1].segments)
                XCTAssertEqual(0x12, table.entries[1].pulses)
                XCTAssertEqual(true, table.entries[1].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[2].segments)
                XCTAssertEqual(0x13, table.entries[2].pulses)
                XCTAssertEqual(false, table.entries[2].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[3].segments)
                XCTAssertEqual(0x12, table.entries[3].pulses)
                XCTAssertEqual(true, table.entries[3].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[4].segments)
                XCTAssertEqual(0x13, table.entries[4].pulses)
                XCTAssertEqual(false, table.entries[4].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[5].segments)
                XCTAssertEqual(0x12, table.entries[5].pulses)
                XCTAssertEqual(true, table.entries[5].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[6].segments)
                XCTAssertEqual(0x13, table.entries[6].pulses)
                XCTAssertEqual(false, table.entries[6].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[7].segments)
                XCTAssertEqual(0x12, table.entries[7].pulses)
                XCTAssertEqual(true, table.entries[7].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[8].segments)
                XCTAssertEqual(0x13, table.entries[8].pulses)
                XCTAssertEqual(false, table.entries[8].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 7c 0bb8 00030d40 0bb8 00927c00
            let extraCmd = try BolusExtraCommand(encodedData: Data(hexadecimalString: "170d7c0bb800030d400bb800927c00")!)
            XCTAssertEqual(15.0, extraCmd.units)
            XCTAssertEqual(false, extraCmd.acknowledgementBeep)
            XCTAssertEqual(true, extraCmd.completionBeep)
            XCTAssertEqual(.minutes(60), extraCmd.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, extraCmd.timeBetweenPulses)
            XCTAssertEqual(15, extraCmd.extendedUnits)
            XCTAssertEqual(.hours(8), extraCmd.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testDualBolusDeliveryEncoding() {
        // 0.10U dual bolus 50% extended over 0.5 hours (1i 2e) -> only one entry used
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp         17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 03231932 02 0015 02 0010 0001 1001         17 0d 00 000a 00030d40 000a 0aba9500
        let bolus_0_10U_50P_ext_30min = SetInsulinScheduleCommand(nonce: 0x03231932, units: 0.05, extendedUnits: 0.05, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a0e0323193202001502001000011001", bolus_0_10U_50P_ext_30min.data.hexadecimalString)

        // 0.10U dual bolus 50% extended over 1.0 hour (1i 2e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp   17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 03011936 02 0016 03 0010 0001 0001 1800   17 0d 00 000a 00030d40 000a 15752a00
        let bolus_0_10U_50P_ext_60min = SetInsulinScheduleCommand(nonce: 0x03011936, units: 0.05, extendedUnits: 0.05, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a1003011936020016030010000100011800", bolus_0_10U_50P_ext_60min.data.hexadecimalString)


        // 0.15U dual bolus 65% extended over 0.5 hours (1i 2e) -> only one entry used
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp             17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 03171958 02 0016 02 0010 0001 1801             17 0d 00 000a 00030d40 0014 055d4a80
        let bolus_0_15U_65P_ext_30min = SetInsulinScheduleCommand(nonce: 0x03171958, units: 0.05, extendedUnits: 0.10, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a0e0317195802001602001000011801", bolus_0_15U_65P_ext_30min.data.hexadecimalString)

        // 0.15U dual bolus 65% extended over 1.0 hour (1i 2e) -> only one entry used
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp             17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 08151959 02 0017 03 0010 0001 2001             17 0d 00 000a 00030d40 0014 0aba9500
        let bolus_0_15U_65P_ext_60min = SetInsulinScheduleCommand(nonce: 0x08151959, units: 0.05, extendedUnits: 0.10, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a0e0815195902001703001000012001", bolus_0_15U_65P_ext_60min.data.hexadecimalString)

        // 0.15U dual bolus 65% extended over 1.5 hours (1i 2e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp   17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 06211961 02 0018 04 0010 0001 0001 1800 0001   17 0d 00 000a 00030d40 0014 1017df80
        let bolus_0_15U_65P_ext_90min = SetInsulinScheduleCommand(nonce: 0x06211961, units: 0.05, extendedUnits: 0.10, extendedDuration: .hours(1.5))
        XCTAssertEqual("1a12062119610200180400100001000118000001", bolus_0_15U_65P_ext_90min.data.hexadecimalString)

        // 0.15U dual bolus 65% extended over 2.0 hours (1i 2e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp        17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 12041962 02 0019 05 0010 0001 0001 3800        17 0d 00 000a 00030d40 0014 15752a00
        let bolus_0_15U_65P_ext_120min = SetInsulinScheduleCommand(nonce: 0x12041962, units: 0.05, extendedUnits: 0.10, extendedDuration: .hours(2.0))
        XCTAssertEqual("1a1012041962020019050010000100013800", bolus_0_15U_65P_ext_120min.data.hexadecimalString)


        // 0.20U dual bolus 75% extended over 0.5 hours (1i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 08121964 02 0017 02 0010 0001 0001 0003            17 0d 00 000a 00030d40 001e 03938700
        let bolus_0_20U_75P_ext_30min = SetInsulinScheduleCommand(nonce: 0x08121964, units: 0.05, extendedUnits: 0.15, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a1008121964020017020010000100010003", bolus_0_20U_75P_ext_30min.data.hexadecimalString)

        // 0.20U dual bolus 75% extended over 1.0 hour (1i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 04111967 02 0018 03 0010 0001 1001 0002            17 0d 00 000a 00030d40 001e 07270e00
        let bolus_0_20U_75P_ext_60min = SetInsulinScheduleCommand(nonce: 0x04111967, units: 0.05, extendedUnits: 0.15, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a1004111967020018030010000110010002", bolus_0_20U_75P_ext_60min.data.hexadecimalString)

        // 0.20U dual bolus 75% extended over 1.5 hours (1i 3e) -> only one entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp                 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 09301968 02 0019 04 0010 0001 3001                 17 0d 00 000a 00030d40 001e 0aba9500
        let bolus_0_20U_75P_ext_90min = SetInsulinScheduleCommand(nonce: 0x09301968, units: 0.05, extendedUnits: 0.15, extendedDuration: .hours(1.5))
        XCTAssertEqual("1a0e0930196802001904001000013001", bolus_0_20U_75P_ext_90min.data.hexadecimalString)

        // 0.20U dual bolus 75% extended over 2.0 hours (1i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp       17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 07271971 02 001a 05 0010 0001 0001 1800 1001       17 0d 00 000a 00030d40 001e 0e4e1c00
        let bolus_0_20U_75P_ext_120min = SetInsulinScheduleCommand(nonce: 0x07271971, units: 0.05, extendedUnits: 0.15, extendedDuration: .hours(2.0))
        XCTAssertEqual("1a120727197102001a0500100001000118001001", bolus_0_20U_75P_ext_120min.data.hexadecimalString)

        // 0.20U dual bolus 75% extended over 2.5 hours (1i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp       17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 03091975 02 001b 06 0010 0001 0001 3800 0001       17 0d 00 000a 00030d40 001e 11e1a300
        let bolus_0_20U_75P_ext_150min = SetInsulinScheduleCommand(nonce: 0x03091975, units: 0.05, extendedUnits: 0.15, extendedDuration: .hours(2.5))
        XCTAssertEqual("1a120309197502001b0600100001000138000001", bolus_0_20U_75P_ext_150min.data.hexadecimalString)

        // 0.20U dual bolus 75% extended over 3.0 hours (1i 3e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 01242016 02 001c 07 0010 0001 0001 5800            17 0d 00 000a 00030d40 001e 15752a00
        let bolus_0_20U_75P_ext_180min = SetInsulinScheduleCommand(nonce: 0x01242016, units: 0.05, extendedUnits: 0.15, extendedDuration: .hours(3.0))
        XCTAssertEqual("1a100124201602001c070010000100015800", bolus_0_20U_75P_ext_180min.data.hexadecimalString)


        // 0.25U dual bolus 80% extended over 0.5 hours (1i 4e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp                    17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 03211983 02 0018 02 0010 0001 0001 0004                    17 0d 00 000a 00030d40 0028 02aea540
        let bolus_0_25U_80P_ext_30min = SetInsulinScheduleCommand(nonce: 0x03211983, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a1003211983020018020010000100010004", bolus_0_25U_80P_ext_30min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 1.0 hour (1i 4e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp                    17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 11041986 02 0019 03 0010 0001 1801 0002                    17 0d 00 000a 00030d40 0028 055d4a80
        let bolus_0_25U_80P_ext_60min = SetInsulinScheduleCommand(nonce: 0x11041986, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a1011041986020019030010000118010002", bolus_0_25U_80P_ext_60min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 1.5 hours (1i 4e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp                    17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 05061987 02 001a 04 0010 0001 2001 0002                    17 0d 00 000a 00030d40 0028 080befc0
        let bolus_0_25U_80P_ext_90min = SetInsulinScheduleCommand(nonce: 0x05061987, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(1.5))
        XCTAssertEqual("1a100506198702001a040010000120010002", bolus_0_25U_80P_ext_90min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 2.0 hours (1i 4e) -> only one entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp                         17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 10201988 02 001b 05 0010 0001 4001                         17 0d 00 000a 00030d40 0028 0aba9500
        let bolus_0_25U_80P_ext_120min = SetInsulinScheduleCommand(nonce: 0x10201988, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(2.0))
        XCTAssertEqual("1a0e1020198802001b05001000014001", bolus_0_25U_80P_ext_120min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 2.5 hours (1i 4e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp               17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 07051989 02 001c 06 0010 0001 0001 1800 2001               17 0d 00 000a 00030d40 0028 0d693a40
        let bolus_0_25U_80P_ext_150min = SetInsulinScheduleCommand(nonce: 0x07051989, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(2.5))
        XCTAssertEqual("1a120705198902001c0600100001000118002001", bolus_0_25U_80P_ext_150min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 3.0 hours (1i 4e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp napp     17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 16 09061990 02 001d 07 0010 0001 0001 1800 0001 1800 0001     17 0d 00 000a 00030d40 0028 1017df80
        let bolus_0_25U_80P_ext_180min = SetInsulinScheduleCommand(nonce: 0x09061990, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(3.0))
        XCTAssertEqual("1a160906199002001d070010000100011800000118000001", bolus_0_25U_80P_ext_180min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 3.5 hours (1i 4e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp               17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 09061990 02 001e 08 0010 0001 0001 5800 0001               17 0d 00 000a 00030d40 0028 12c684c0
        let bolus_0_25U_80P_ext_210min = SetInsulinScheduleCommand(nonce: 0x09061990, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(3.5))
        XCTAssertEqual("1a120906199002001e0800100001000158000001", bolus_0_25U_80P_ext_210min.data.hexadecimalString)

        // 0.25U dual bolus 80% extended over 4.0 hours (1i 4e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp                    17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 01311991 02 001f 09 0010 0001 0001 7800                    17 0d 00 000a 00030d40 0028 15752a00
        let bolus_0_25U_80P_ext_240min = SetInsulinScheduleCommand(nonce: 0x01311991, units: 0.05, extendedUnits: 0.20, extendedDuration: .hours(4.0))
        XCTAssertEqual("1a100131199102001f090010000100017800", bolus_0_25U_80P_ext_240min.data.hexadecimalString)


        // 0.15U dual bolus 30% extended over 0.5 hours (2i 1e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 05071991 02 0027 02 0020 0002 0002 0001            17 0d 00 0014 00030d40 000a 0aba9500
        let bolus_0_15U_30P_ext_30min = SetInsulinScheduleCommand(nonce: 0x05071991, units: 0.10, extendedUnits: 0.05, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a1005071991020027020020000200020001", bolus_0_15U_30P_ext_30min.data.hexadecimalString)

        // 0.15U dual bolus 30% extended over 1.0 hour (2i 1e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 08311995 02 0028 03 0020 0002 0002 1800            17 0d 00 0014 00030d40 000a 15752a00
        let bolus_0_15U_30P_ext_60min = SetInsulinScheduleCommand(nonce: 0x08311995, units: 0.10, extendedUnits: 0.05, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a1008311995020028030020000200021800", bolus_0_15U_30P_ext_60min.data.hexadecimalString)


        // 0.20U dual bolus 50% extended over 0.5 hours (2i 2e) -> only one entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp                 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 10061995 02 0028 02 0020 0002 1002                 17 0d 00 0014 00030d40 0014 055d4a80
        let bolus_0_20U_50P_ext_30min = SetInsulinScheduleCommand(nonce: 0x10061995, units: 0.10, extendedUnits: 0.10, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a0e1006199502002802002000021002", bolus_0_20U_50P_ext_30min.data.hexadecimalString)

        // 0.20U dual bolus 50% extended over 1.0 hour (2i 2e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 07132004 02 0029 03 0020 0002 0002 1001            17 0d 00 0014 00030d40 0014 0aba9500
        let bolus_0_20U_50P_ext_60min = SetInsulinScheduleCommand(nonce: 0x07132004, units: 0.10, extendedUnits: 0.10, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a1007132004020029030020000200021001", bolus_0_20U_50P_ext_60min.data.hexadecimalString)

        // 0.20U dual bolus 50% extended over 1.5 hours (2i 2e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 02192008 02 002a 04 0020 0002 0002 1800 0001       17 0d 00 0014 00030d40 0014 1017df80
        let bolus_0_20U_50P_ext_90min = SetInsulinScheduleCommand(nonce: 0x02192008, units: 0.10, extendedUnits: 0.10, extendedDuration: .hours(1.5))
        XCTAssertEqual("1a120219200802002a0400200002000218000001", bolus_0_20U_50P_ext_90min.data.hexadecimalString)

        // 0.20U dual bolus 50% extended over 2.0 hours (2i 2e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 10092008 02 002b 05 0020 0002 0002 3800            17 0d 00 0014 00030d40 0014 15752a00
        let bolus_0_20U_50P_ext_120min = SetInsulinScheduleCommand(nonce: 0x10092008, units: 0.10, extendedUnits: 0.10, extendedDuration: .hours(2.0))
        XCTAssertEqual("1a101009200802002b050020000200023800", bolus_0_20U_50P_ext_120min.data.hexadecimalString)


        // 0.25U dual bolus 60% extended over 0.5 hours (2i 3e) -> only one entry
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp                 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 0e 06222009 02 0029 02 0020 0002 1802                 17 0d 00 0014 00030d40 001e 03938700
        let bolus_0_25U_60P_ext_30min = SetInsulinScheduleCommand(nonce: 0x06222009, units: 0.10, extendedUnits: 0.15, extendedDuration: .hours(0.5))
        XCTAssertEqual("1a0e0622200902002902002000021802", bolus_0_25U_60P_ext_30min.data.hexadecimalString)

        // 0.25U dual bolus 60% extended over 1.0 hour (2i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 07122009 02 002a 03 0020 0002 0002 1801            17 0d 00 0014 00030d40 001e 07270e00
        let bolus_0_25U_60P_ext_60min = SetInsulinScheduleCommand(nonce: 0x07122009, units: 0.10, extendedUnits: 0.15, extendedDuration: .hours(1.0))
        XCTAssertEqual("1a100712200902002a030020000200021801", bolus_0_25U_60P_ext_60min.data.hexadecimalString)

        // 0.25U dual bolus 60% extended over 1.5 hours (2i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 08102009 02 002b 04 0020 0002 0002 2001            17 0d 00 0014 00030d40 001e 0aba9500
        let bolus_0_25U_60P_ext_90min = SetInsulinScheduleCommand(nonce: 0x08102009, units: 0.10, extendedUnits: 0.15, extendedDuration: .hours(1.5))
        XCTAssertEqual("1a100810200902002b040020000200022001", bolus_0_25U_60P_ext_90min.data.hexadecimalString)

        // 0.25U dual bolus 60% extended over 2.0 hours (2i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp       17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 07162010 02 002c 05 0020 0002 0002 1800 1001       17 0d 00 0014 00030d40 001e 0e4e1c00
        let bolus_0_25U_60P_ext_120min = SetInsulinScheduleCommand(nonce: 0x07162010, units: 0.10, extendedUnits: 0.15, extendedDuration: .hours(2.0))
        XCTAssertEqual("1a120716201002002c0500200002000218001001", bolus_0_25U_60P_ext_120min.data.hexadecimalString)

        // 0.25U dual bolus 60% extended over 2.5 hours (2i 3e)
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp       17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 12 08072010 02 002d 06 0020 0002 0002 3800 0001       17 0d 00 0014 00030d40 001e 11e1a300
        let bolus_0_25U_60P_ext_150min = SetInsulinScheduleCommand(nonce: 0x08072010, units: 0.10, extendedUnits: 0.15, extendedDuration: .hours(2.5))
        XCTAssertEqual("1a120807201002002d0600200002000238000001", bolus_0_25U_60P_ext_150min.data.hexadecimalString)

        // 0.25U dual bolus 60% extended over 3.0 hours (2i 3e) -> max duration allowed
        // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp            17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 1a 10 05062012 02 002e 07 0020 0002 0002 5800            17 0d 00 0014 00030d40 001e 15752a00
        let bolus_0_25U_60P_ext_180min = SetInsulinScheduleCommand(nonce: 0x05062012, units: 0.10, extendedUnits: 0.15, extendedDuration: .hours(3.0))
        XCTAssertEqual("1a100506201202002e070020000200025800", bolus_0_25U_60P_ext_180min.data.hexadecimalString)
    }

    func test_30U_100P_ext() {
        // 30U bolus 100% ext over 0.5 hours (0i 600e)
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
            // 1a 10 494e532e 02 005c 02 0000 0000 0000 0258
            let bolus30U_100P_ext_30min = SetInsulinScheduleCommand(nonce: 0x494e532e, units: 0.0, extendedUnits: 30, extendedDuration: .hours(0.5))
            XCTAssertEqual("1a10494e532e02005c020000000000000258", bolus30U_100P_ext_30min.data.hexadecimalString)

            let bolus30U_100P_ext_30min_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus30U_100P_ext_30min.data.hexadecimalString)!)
            XCTAssertEqual(0x494e532e, bolus30U_100P_ext_30min_encoded.nonce)
            let schedule = bolus30U_100P_ext_30min_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(0.0, units)
                XCTAssertEqual(0, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(0, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[1].segments)
                XCTAssertEqual(600, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 0000 00030d40 1770 000493e0
            let bolus30U_100P_ext_30min_extra = BolusExtraCommand(extendedUnits: 30.0, extendedDuration: .hours(0.5))
            XCTAssertEqual("170d00000000030d401770000493e0", bolus30U_100P_ext_30min_extra.data.hexadecimalString)

            let bolus30U_100P_ext_30min_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus30U_100P_ext_30min_extra.data.hexadecimalString)!)
            XCTAssertEqual(0.0, bolus30U_100P_ext_30min_extra_encoded.units)
            XCTAssertEqual(false, bolus30U_100P_ext_30min_extra_encoded.acknowledgementBeep)
            XCTAssertEqual(false, bolus30U_100P_ext_30min_extra_encoded.completionBeep)
            XCTAssertEqual(0, bolus30U_100P_ext_30min_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus30U_100P_ext_30min_extra_encoded.timeBetweenPulses)
            XCTAssertEqual(30.0, bolus30U_100P_ext_30min_extra_encoded.extendedUnits)
            XCTAssertEqual(.hours(0.5), bolus30U_100P_ext_30min_extra_encoded.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func test_30U_75P_ext() {
        // 30U bolus 75% ext over 0.5 hours (450i 150e)
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
            // 1a 10 494e532e 02 025a 02 0960 0096 0096 01c2
            let bolus30U_75P_ext_30min = SetInsulinScheduleCommand(nonce: 0x494e532e, units: 7.5, extendedUnits: 22.5, extendedDuration: .hours(0.5))
            XCTAssertEqual("1a10494e532e02025a0209600096009601c2", bolus30U_75P_ext_30min.data.hexadecimalString)

            let bolus30U_75P_ext_30min_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus30U_75P_ext_30min.data.hexadecimalString)!)
            XCTAssertEqual(0x494e532e, bolus30U_75P_ext_30min_encoded.nonce)
            let schedule = bolus30U_75P_ext_30min_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(7.5, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(150, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[1].segments)
                XCTAssertEqual(450, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 05dc 00030d40 1194 00061a80
            let bolus30U_75P_ext_30min_extra = BolusExtraCommand(units: 7.5, extendedUnits: 22.5, extendedDuration: .hours(0.5))
            XCTAssertEqual("170d0005dc00030d40119400061a80", bolus30U_75P_ext_30min_extra.data.hexadecimalString)

            let bolus30U_75P_ext_30min_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus30U_75P_ext_30min_extra.data.hexadecimalString)!)
            XCTAssertEqual(7.5, bolus30U_75P_ext_30min_extra_encoded.units)
            XCTAssertEqual(false, bolus30U_75P_ext_30min_extra_encoded.acknowledgementBeep)
            XCTAssertEqual(false, bolus30U_75P_ext_30min_extra_encoded.completionBeep)
            XCTAssertEqual(0, bolus30U_75P_ext_30min_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus30U_75P_ext_30min_extra_encoded.timeBetweenPulses)
            XCTAssertEqual(22.5, bolus30U_75P_ext_30min_extra_encoded.extendedUnits)
            XCTAssertEqual(.hours(0.5), bolus30U_75P_ext_30min_extra_encoded.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func test_30U_50P_ext() {
        // 30U bolus 50% ext over 0.5 hours (300i 300e)
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp
            // 1a 0e 494e532e 02 015b 02 12c0 012c 112c
            let bolus30U_50P_ext_30min = SetInsulinScheduleCommand(nonce: 0x494e532e, units: 15.0, extendedUnits: 15.0, extendedDuration: .hours(0.5))
            XCTAssertEqual("1a0e494e532e02015b0212c0012c112c", bolus30U_50P_ext_30min.data.hexadecimalString)

            let bolus30U_50P_ext_30min_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus30U_50P_ext_30min.data.hexadecimalString)!)
            XCTAssertEqual(0x494e532e, bolus30U_50P_ext_30min_encoded.nonce)
            let schedule = bolus30U_50P_ext_30min_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(15.0, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(1, table.entries.count)
                XCTAssertEqual(2, table.entries[0].segments)
                XCTAssertEqual(300, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 0bb8 00030d40 0bb8 000927c0
            let bolus30U_50P_ext_30min_extra = BolusExtraCommand(units: 15.0, extendedUnits: 15.0, extendedDuration: .hours(0.5))
            XCTAssertEqual("170d000bb800030d400bb8000927c0", bolus30U_50P_ext_30min_extra.data.hexadecimalString)

            let bolus30U_50P_ext_30min_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus30U_50P_ext_30min_extra.data.hexadecimalString)!)
            XCTAssertEqual(15.0, bolus30U_50P_ext_30min_extra_encoded.units)
            XCTAssertEqual(false, bolus30U_50P_ext_30min_extra_encoded.acknowledgementBeep)
            XCTAssertEqual(false, bolus30U_50P_ext_30min_extra_encoded.completionBeep)
            XCTAssertEqual(0, bolus30U_50P_ext_30min_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus30U_50P_ext_30min_extra_encoded.timeBetweenPulses)
            XCTAssertEqual(15.0, bolus30U_50P_ext_30min_extra_encoded.extendedUnits)
            XCTAssertEqual(.hours(0.5), bolus30U_50P_ext_30min_extra_encoded.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func test_30U_25P_ext() {
        // 30U bolus 25% ext over 0.5 hours (450i 150e)
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
            // 1a 10 494e532e 02 025a 02 1c20 01c2 01c2 0096
            let bolus30U_25P_ext_30min = SetInsulinScheduleCommand(nonce: 0x494e532e, units: 22.5, extendedUnits: 7.5, extendedDuration: .hours(0.5))
            XCTAssertEqual("1a10494e532e02025a021c2001c201c20096", bolus30U_25P_ext_30min.data.hexadecimalString)

            let bolus30U_25P_ext_30min_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus30U_25P_ext_30min.data.hexadecimalString)!)
            XCTAssertEqual(0x494e532e, bolus30U_25P_ext_30min_encoded.nonce)
            let schedule = bolus30U_25P_ext_30min_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(22.5, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(450, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[1].segments)
                XCTAssertEqual(150, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 1194 00030d40 05dc 00124f80
            let bolus30U_25P_ext_30min_extra = BolusExtraCommand(units: 22.5, extendedUnits: 7.5, extendedDuration: .hours(0.5))
            XCTAssertEqual("170d00119400030d4005dc00124f80", bolus30U_25P_ext_30min_extra.data.hexadecimalString)

            let bolus30U_25P_ext_30min_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus30U_25P_ext_30min_extra.data.hexadecimalString)!)
            XCTAssertEqual(22.5, bolus30U_25P_ext_30min_extra_encoded.units)
            XCTAssertEqual(false, bolus30U_25P_ext_30min_extra_encoded.acknowledgementBeep)
            XCTAssertEqual(false, bolus30U_25P_ext_30min_extra_encoded.completionBeep)
            XCTAssertEqual(0, bolus30U_25P_ext_30min_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus30U_25P_ext_30min_extra_encoded.timeBetweenPulses)
            XCTAssertEqual(7.5, bolus30U_25P_ext_30min_extra_encoded.extendedUnits)
            XCTAssertEqual(.hours(0.5), bolus30U_25P_ext_30min_extra_encoded.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func test_1U_immediate_9123secs_remaining() {
        // extended bolus of 1.0U over 3.5 hours
        // immediate 1.0U bolus with 2:32:05 (9123 seconds) remaining, cancel bolus returns 15 pulses (0.75U) not delivered
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp napp napp
            // 1a 14 d3039c04 02 007f 07 0140 0014 0014 1802 2003 0001
            let nonce: UInt32 = 0xd3039c04
            let immediateUnits = 1.0
            let remainingExtendedUnits = 0.75
            let remainingExtendedBolusTime: TimeInterval = .seconds(9123)

            let bolus_1U_immediate_9123secs_remaining = SetInsulinScheduleCommand(nonce: nonce, units: immediateUnits, extendedUnits: remainingExtendedUnits, extendedDuration: remainingExtendedBolusTime)
            XCTAssertEqual("1a14d3039c0402007f07014000140014180220030001", bolus_1U_immediate_9123secs_remaining.data.hexadecimalString)

            let bolus_1U_immediate_9123secs_remaining_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus_1U_immediate_9123secs_remaining.data.hexadecimalString)!)
            XCTAssertEqual(nonce, bolus_1U_immediate_9123secs_remaining.nonce)
            let schedule = bolus_1U_immediate_9123secs_remaining_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(immediateUnits, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(4, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(20, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[1].segments)
                XCTAssertEqual(2, table.entries[1].pulses)
                XCTAssertEqual(true, table.entries[1].alternateSegmentPulse)
                XCTAssertEqual(3, table.entries[2].segments)
                XCTAssertEqual(3, table.entries[2].pulses)
                XCTAssertEqual(false, table.entries[2].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[3].segments)
                XCTAssertEqual(1, table.entries[3].pulses)
                XCTAssertEqual(false, table.entries[3].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 00c8 00030d40 0096 03a00a20
            let bolus_1U_immediate_9123secs_remaining_extra = BolusExtraCommand(units: immediateUnits, extendedUnits: remainingExtendedUnits, extendedDuration: remainingExtendedBolusTime)
            XCTAssertEqual("170d0000c800030d40009603a00a20", bolus_1U_immediate_9123secs_remaining_extra.data.hexadecimalString)
            let bolus_1U_immediate_9123secs_remaining_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus_1U_immediate_9123secs_remaining_extra.data.hexadecimalString)!)
            XCTAssertEqual(immediateUnits, bolus_1U_immediate_9123secs_remaining_extra_encoded.units)
            XCTAssertEqual(false, bolus_1U_immediate_9123secs_remaining_extra.acknowledgementBeep)
            XCTAssertEqual(false, bolus_1U_immediate_9123secs_remaining_extra.completionBeep)
            XCTAssertEqual(0, bolus_1U_immediate_9123secs_remaining_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus_1U_immediate_9123secs_remaining_extra.timeBetweenPulses)
            XCTAssertEqual(remainingExtendedUnits, bolus_1U_immediate_9123secs_remaining_extra_encoded.extendedUnits)
            XCTAssertEqual(remainingExtendedBolusTime, bolus_1U_immediate_9123secs_remaining_extra.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func test_1U_immediate_3363secs_remaining() {
        // extended bolus of 1.0U over 3.5 hours
        // immediate 1.0U bolus with 56:03 min (3363 seconds) remaining, cancel bolus returns 6 pulses (0.30U) not delivered
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
            // 1a 10 1304de22 02 0072 03 0140 0014 0014 1003
            let nonce: UInt32 = 0x1304de22
            let immediateUnits = 1.0
            let remainingExtendedUnits = 0.3
            let remainingExtendedBolusTime: TimeInterval = .seconds(3363)

            let bolus_1U_immediate_3363secs_remaining = SetInsulinScheduleCommand(nonce: nonce, units: immediateUnits, extendedUnits: remainingExtendedUnits, extendedDuration: remainingExtendedBolusTime)
            XCTAssertEqual("1a101304de22020072030140001400141003", bolus_1U_immediate_3363secs_remaining.data.hexadecimalString)

            let bolus_1U_immediate_3363secs_remaining_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus_1U_immediate_3363secs_remaining.data.hexadecimalString)!)
            XCTAssertEqual(nonce, bolus_1U_immediate_3363secs_remaining.nonce)
            let schedule = bolus_1U_immediate_3363secs_remaining_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(immediateUnits, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(20, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(2, table.entries[1].segments)
                XCTAssertEqual(3, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 00c8 00030d40 003c 03574150
            let bolus_1U_immediate_3363secs_remaining_extra = BolusExtraCommand(units: immediateUnits, extendedUnits: remainingExtendedUnits, extendedDuration: remainingExtendedBolusTime)
            XCTAssertEqual("170d0000c800030d40003c03574150", bolus_1U_immediate_3363secs_remaining_extra.data.hexadecimalString)
            let bolus_1U_immediate_3363secs_remaining_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus_1U_immediate_3363secs_remaining_extra.data.hexadecimalString)!)
            XCTAssertEqual(immediateUnits, bolus_1U_immediate_3363secs_remaining_extra_encoded.units)
            XCTAssertEqual(false, bolus_1U_immediate_3363secs_remaining_extra.acknowledgementBeep)
            XCTAssertEqual(false, bolus_1U_immediate_3363secs_remaining_extra.completionBeep)
            XCTAssertEqual(0, bolus_1U_immediate_3363secs_remaining_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus_1U_immediate_3363secs_remaining_extra.timeBetweenPulses)
            XCTAssertEqual(remainingExtendedUnits, bolus_1U_immediate_3363secs_remaining_extra_encoded.extendedUnits)
            XCTAssertEqual(remainingExtendedBolusTime, bolus_1U_immediate_3363secs_remaining_extra.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func test_1U_immediate_382secs_remaining() {
        // extended bolus of 1.0U over 3.5 hours
        // immediate 1.0U bolus with 6:22 (382 seconds) remaining, cancel bolus returns 1 pulse (0.05U) not delivered
        do {
            // 1a LL NNNNNNNN 02 CCCC HH SSSS PPPP napp napp
            // 1a 10 10bbea5c 02 006c 02 0140 0014 0014 0001
            let nonce: UInt32 = 0x10bbea5c
            let immediateUnits = 1.0
            let remainingExtendedUnits = 0.05
            let remainingExtendedBolusTime: TimeInterval = .seconds(382)

            let bolus_1U_immediate_382secs_remaining = SetInsulinScheduleCommand(nonce: nonce, units: immediateUnits, extendedUnits: remainingExtendedUnits, extendedDuration: remainingExtendedBolusTime)
            XCTAssertEqual("1a1010bbea5c02006c020140001400140001", bolus_1U_immediate_382secs_remaining.data.hexadecimalString)

            let bolus_1U_immediate_382secs_remaining_encoded = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: bolus_1U_immediate_382secs_remaining.data.hexadecimalString)!)
            XCTAssertEqual(nonce, bolus_1U_immediate_382secs_remaining.nonce)
            let schedule = bolus_1U_immediate_382secs_remaining_encoded.deliverySchedule
            switch schedule {
            case .bolus(let units, let timeBetweenPulses, let table):
                XCTAssertEqual(immediateUnits, units)
                XCTAssertEqual(Pod.secondsPerBolusPulse, timeBetweenPulses)
                XCTAssertEqual(2, table.entries.count)
                XCTAssertEqual(1, table.entries[0].segments)
                XCTAssertEqual(20, table.entries[0].pulses)
                XCTAssertEqual(false, table.entries[0].alternateSegmentPulse)
                XCTAssertEqual(1, table.entries[1].segments)
                XCTAssertEqual(1, table.entries[1].pulses)
                XCTAssertEqual(false, table.entries[1].alternateSegmentPulse)
            default:
                XCTFail("unexpected insulin delivery type \(schedule)")
                break
            }

            // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
            // 17 0d 00 00c8 00030d40 000a 0246e2c0
            let bolus_1U_immediate_382secs_remaining_extra = BolusExtraCommand(units: immediateUnits, extendedUnits: remainingExtendedUnits, extendedDuration: remainingExtendedBolusTime)
            XCTAssertEqual("170d0000c800030d40000a0246e2c0", bolus_1U_immediate_382secs_remaining_extra.data.hexadecimalString)
            let bolus_1U_immediate_382secs_remaining_extra_encoded = try BolusExtraCommand(encodedData: Data(hexadecimalString: bolus_1U_immediate_382secs_remaining_extra.data.hexadecimalString)!)
            XCTAssertEqual(immediateUnits, bolus_1U_immediate_382secs_remaining_extra_encoded.units)
            XCTAssertEqual(false, bolus_1U_immediate_382secs_remaining_extra.acknowledgementBeep)
            XCTAssertEqual(false, bolus_1U_immediate_382secs_remaining_extra.completionBeep)
            XCTAssertEqual(0, bolus_1U_immediate_382secs_remaining_extra_encoded.programReminderInterval)
            XCTAssertEqual(Pod.secondsPerBolusPulse, bolus_1U_immediate_382secs_remaining_extra.timeBetweenPulses)
            XCTAssertEqual(remainingExtendedUnits, bolus_1U_immediate_382secs_remaining_extra_encoded.extendedUnits)
            XCTAssertEqual(remainingExtendedBolusTime, bolus_1U_immediate_382secs_remaining_extra.extendedDuration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testBolusExtraOddPulseCount() {
        // 17 0d 7c 00fa 00030d40 000000000000
        let cmd = BolusExtraCommand(units: 1.25, acknowledgementBeep: false, completionBeep: true, programReminderInterval: .hours(1))
        XCTAssertEqual("170d7c00fa00030d40000000000000", cmd.data.hexadecimalString)
    }

    //    1a 0e NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp  17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
    //    1a 0e 19e4890b 02 0025 01 0020 0002 0002  17 0d 00 001e 00030d40 0000 00000000
    //    0ppp = $0002                     -> 2 pulses
    //    NNNN = $001e = 30 (dec) / 10     -> 3 pulses
    func testBolusAndBolusExtraMatch() {
        // 1a 0e NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp
        // 1a 0e 243085c8 02 0025 01 0020 0002 0002
        let bolusAmount = 0.1
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0x243085c8, units: bolusAmount)
        XCTAssertEqual("1a0e243085c802002501002000020002", bolusCommand.data.hexadecimalString)

        // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 17 0d 00 0014 00030d40 0000 00000000
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount)
        XCTAssertEqual("170d00001400030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }

    func testBolusAndBolusExtraMatch2() {
        let bolusAmount = 0.15
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0x243085c8, units: bolusAmount)
        XCTAssertEqual("1a0e243085c802003701003000030003", bolusCommand.data.hexadecimalString)
        
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount)
        XCTAssertEqual("170d00001e00030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }
    
    func testLargeBolus() {
        let bolusAmount = 29.95
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0x31204ba7, units: bolusAmount)
        XCTAssertEqual("1a0e31204ba702014801257002570257", bolusCommand.data.hexadecimalString)
        
        let bolusExtraCommand = BolusExtraCommand(units: bolusAmount, acknowledgementBeep: false, completionBeep: true, programReminderInterval: .hours(1))
        XCTAssertEqual("170d7c176600030d40000000000000", bolusExtraCommand.data.hexadecimalString)
    }
    
    func testOddBolus() {
        // 1a 0e NNNNNNNN 02 CCCC HH SSSS PPPP 0ppp
        // 1a 0e cf9e81ac 02 00e5 01 0290 0029 0029

        let bolusAmount = 2.05
        let bolusCommand = SetInsulinScheduleCommand(nonce: 0xcf9e81ac, units: bolusAmount)
        XCTAssertEqual("1a0ecf9e81ac0200e501029000290029", bolusCommand.data.hexadecimalString)
        
        // 17 LL BO NNNN XXXXXXXX YYYY ZZZZZZZZ
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
