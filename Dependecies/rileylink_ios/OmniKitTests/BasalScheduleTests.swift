//
//  BasalScheduleTests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 4/4/18.
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import OmniKit

class BasalScheduleTests: XCTestCase {
    
    func testBasalTableEntry() {
        let entry = BasalTableEntry(segments: 2, pulses: 300, alternateSegmentPulse: false)
        // $01 $2c $01 $2c = 1 + 44 + 1 + 44 = 90 = $5a
        XCTAssertEqual(0x5a, entry.checksum())
        
        let entry2 = BasalTableEntry(segments: 2, pulses: 260, alternateSegmentPulse: true)
        // $01 $04 $01 $04 = 1 + 4 + 1 + 5 = 1 = $0b
        XCTAssertEqual(0x0b, entry2.checksum())
    }
    
    func testSetBasalScheduleCommand() {
        do {
            // Decode 1a 12 77a05551 00 0062 2b 1708 0000 f800 f800 f800
            let cmd = try SetInsulinScheduleCommand(encodedData: Data(hexadecimalString: "1a1277a055510000622b17080000f800f800f800")!)
            
            XCTAssertEqual(0x77a05551, cmd.nonce)
            if case SetInsulinScheduleCommand.DeliverySchedule.basalSchedule(let currentSegment, let secondsRemaining, let pulsesRemaining, let table) = cmd.deliverySchedule {
                XCTAssertEqual(0x2b, currentSegment)
                XCTAssertEqual(737, secondsRemaining)
                XCTAssertEqual(0, pulsesRemaining)
                XCTAssertEqual(3, table.entries.count)
            } else {
                XCTFail("Expected ScheduleEntry.basalSchedule type")
            }
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let scheduleEntry = BasalTableEntry(segments: 16, pulses: 0, alternateSegmentPulse: true)
        let table = BasalDeliveryTable(entries: [scheduleEntry, scheduleEntry, scheduleEntry])
        let deliverySchedule = SetInsulinScheduleCommand.DeliverySchedule.basalSchedule(currentSegment: 0x2b, secondsRemaining: 737, pulsesRemaining: 0, table: table)
        let cmd = SetInsulinScheduleCommand(nonce: 0x77a05551, deliverySchedule: deliverySchedule)
        XCTAssertEqual("1a1277a055510000622b17080000f800f800f800", cmd.data.hexadecimalString)
    }
    
    func testBasalScheduleCommandFromSchedule() {
        // Encode from schedule
        let entry = BasalScheduleEntry(rate: 0.05, startTime: 0)
        let schedule = BasalSchedule(entries: [entry])
        
        let cmd = SetInsulinScheduleCommand(nonce: 0x01020304, basalSchedule: schedule, scheduleOffset: .hours(8.25))
        
        XCTAssertEqual(0x01020304, cmd.nonce)
        if case SetInsulinScheduleCommand.DeliverySchedule.basalSchedule(let currentSegment, let secondsRemaining, let pulsesRemaining, let table) = cmd.deliverySchedule {
            XCTAssertEqual(16, currentSegment)
            XCTAssertEqual(UInt16(TimeInterval(minutes: 15)), secondsRemaining)
            XCTAssertEqual(0, pulsesRemaining)
            XCTAssertEqual(3, table.entries.count)
            let tableEntry = table.entries[0]
            XCTAssertEqual(true, tableEntry.alternateSegmentPulse)
            XCTAssertEqual(0, tableEntry.pulses)
            XCTAssertEqual(16, tableEntry.segments)
        } else {
            XCTFail("Expected ScheduleEntry.basalSchedule type")
        }
        // 1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp
        // 1a 12 01020304 00 0065 10 1c20 0001 f800 f800 f800
        XCTAssertEqual("1a1201020304000064101c200000f800f800f800", cmd.data.hexadecimalString)
    }

    
    func testBasalScheduleExtraCommand() {
        do {
            // Decode 130e40 00 1aea 001e8480 3840005b8d80
            
            let cmd = try BasalScheduleExtraCommand(encodedData: Data(hexadecimalString: "130e40001aea001e84803840005b8d80")!)
            
            XCTAssertEqual(false, cmd.acknowledgementBeep)
            XCTAssertEqual(true, cmd.completionBeep)
            XCTAssertEqual(0, cmd.programReminderInterval)
            XCTAssertEqual(0, cmd.currentEntryIndex)
            XCTAssertEqual(689, cmd.remainingPulses)
            XCTAssertEqual(TimeInterval(seconds: 20), cmd.delayUntilNextTenthOfPulse)
            XCTAssertEqual(1, cmd.rateEntries.count)
            let entry = cmd.rateEntries[0]
            XCTAssertEqual(TimeInterval(seconds: 60), entry.delayBetweenPulses)
            XCTAssertEqual(1440, entry.totalPulses)
            XCTAssertEqual(3.0, entry.rate)
            XCTAssertEqual(TimeInterval(hours: 24), entry.duration)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let rateEntries = RateEntry.makeEntries(rate: 3.0, duration: TimeInterval(hours: 24))
        let cmd = BasalScheduleExtraCommand(currentEntryIndex: 0, remainingPulses: 689, delayUntilNextTenthOfPulse: TimeInterval(seconds: 20), rateEntries: rateEntries, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)


        XCTAssertEqual("130e40001aea01312d003840005b8d80", cmd.data.hexadecimalString)
    }
    
    func testBasalScheduleExtraCommandFromSchedule() {
        // Encode from schedule
        let entry = BasalScheduleEntry(rate: 0.05, startTime: 0)
        let schedule = BasalSchedule(entries: [entry])
        
        let cmd = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: .hours(8.25), acknowledgementBeep: false, completionBeep: true, programReminderInterval: 60)
        
        XCTAssertEqual(false, cmd.acknowledgementBeep)
        XCTAssertEqual(true, cmd.completionBeep)
        XCTAssertEqual(60, cmd.programReminderInterval)
        XCTAssertEqual(0, cmd.currentEntryIndex)
        XCTAssertEqual(15.8, cmd.remainingPulses, accuracy: 0.01)
        XCTAssertEqual(TimeInterval(minutes: 3), cmd.delayUntilNextTenthOfPulse)
        XCTAssertEqual(1, cmd.rateEntries.count)
        let rateEntry = cmd.rateEntries[0]
        XCTAssertEqual(TimeInterval(minutes: 60), rateEntry.delayBetweenPulses)
        XCTAssertEqual(24, rateEntry.totalPulses, accuracy: 0.001)
        XCTAssertEqual(0.05, rateEntry.rate)
        XCTAssertEqual(TimeInterval(hours: 24), rateEntry.duration, accuracy: 0.001)
    }
    
    func testBasalExtraEncoding() {
        // Encode
        
        let schedule = BasalSchedule(entries: [
            BasalScheduleEntry(rate: 1.05, startTime: 0),
            BasalScheduleEntry(rate: 0.9, startTime: .hours(10.5)),
            BasalScheduleEntry(rate: 1, startTime: .hours(18.5))
            ])
        
        let hh = 0x2e
        let ssss = 0x1be8
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        // 1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp
        // 1a 14 0d6612db 00 0310 2e 1be8 0005 f80a 480a f009 a00a

        let cmd1 = SetInsulinScheduleCommand(nonce: 0x0d6612db, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a140d6612db0003102e1be80005f80a480af009a00a", cmd1.data.hexadecimalString)

        // 13 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // 13 1a 40 02 0096 00a7d8c0 089d 01059449 05a0 01312d00 044c 0112a880  * PDM
        // 13 1a 40 02 0095 00a7d8c0 089d 01059449 05a0 01312d00 044c 0112a880
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        XCTAssertEqual("131a4002009600a7d8c0089d0105944905a001312d00044c0112a880", cmd2.data.hexadecimalString) // PDM
    }
    
    func checkBasalScheduleExtraCommandDataWithLessPrecision(_ data: Data, _ expected: Data, line: UInt = #line) {
        // The XXXXXXXX field is in thousands of a millisecond. Since we use TimeIntervals (floating point) for
        // recreating the offset, we can have small errors in reproducing the the encoded output, which we really
        // don't care about.
        
        func extractXXXXXXXX(_ data: Data) -> TimeInterval {
            return TimeInterval(Double(data[6...].toBigEndian(UInt32.self)) / 1000000.0)
        }
        
        let xxxxxxxx1 = extractXXXXXXXX(data)
        let xxxxxxxx2 = extractXXXXXXXX(expected)
        XCTAssertEqual(xxxxxxxx1, xxxxxxxx2, accuracy: 0.01, line: line)
        
        func blurXXXXXXXX(_ inStr: String) -> String {
            let start = inStr.index(inStr.startIndex, offsetBy:12)
            let end = inStr.index(start, offsetBy:8)
            return inStr.replacingCharacters(in: start..<end, with: "........")
        }
        print(blurXXXXXXXX(data.hexadecimalString))
        XCTAssertEqual(blurXXXXXXXX(data.hexadecimalString), blurXXXXXXXX(expected.hexadecimalString), line: line)
    }

    func testBasalExtraEncoding1() {
        // Encode
        
        let schedule = BasalSchedule(entries: [BasalScheduleEntry(rate: 1.05, startTime: 0)])
        
        let hh       = 0x20       // 16:00, rate = 1.05
        let ssss     = 0x33c0     // 1656s left, 144s into segment
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        // 1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp
        // 1a 12 2a845e17 00 0314 20 33c0 0009 f80a f80a f80a
        // 1a 12 2a845e17 00 0315 20 33c0 000a f80a f80a f80a

        let cmd1 = SetInsulinScheduleCommand(nonce: 0x2a845e17, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a122a845e170003142033c00009f80af80af80a", cmd1.data.hexadecimalString)
        
        
        // 13 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 13 0e 40 00 0688 009cf291 13b0 01059449
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "130e40000688009cf29113b001059449")!, cmd2.data)
    }
    
    func testBasalExtraEncoding2() {
        // Encode
        
        let schedule = BasalSchedule(entries: [BasalScheduleEntry(rate: 1.05, startTime: 0)])
        
        // 17:47:27 1a 12 0a229e93 00 02d6 23 17a0 0004 f80a f80a f80a 13 0e 40 00 0519 001a2865 13b0 01059449 0220
        
        let hh       = 0x23       // 17:30, rate = 1.05
        let ssss     = 0x17a0     // 756s left, 1044s into segment
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        // 1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp
        // 1a 12 0a229e93 00 02d6 23 17a0 0004 f80a f80a f80a
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x0a229e93, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a120a229e930002d62317a00004f80af80af80a", cmd1.data.hexadecimalString)
        
        
        // 13 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 13 0e 40 00 0519 001a2865 13b0 01059449
        // 13 0e 40 00 0519 001a286e 13b0 01059449
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "130e40000519001a286513b001059449")!, cmd2.data)
    }

    func testSuspendBasalCommand() {
        do {
            // Decode 1f 05 6fede14a 01
            let cmd = try CancelDeliveryCommand(encodedData: Data(hexadecimalString: "1f056fede14a01")!)
            XCTAssertEqual(0x6fede14a, cmd.nonce)
            XCTAssertEqual(.noBeep, cmd.beepType)
            XCTAssertEqual(.basal, cmd.deliveryType)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
        
        // Encode
        let cmd = CancelDeliveryCommand(nonce: 0x6fede14a, deliveryType: .basal, beepType: .noBeep)
        XCTAssertEqual("1f056fede14a01", cmd.data.hexadecimalString)
    }
    
    func testSegmentMerging() {
        let entries = [
            BasalScheduleEntry(rate: 0.80, startTime: 0),
            BasalScheduleEntry(rate: 0.90, startTime: .hours(3)),
            BasalScheduleEntry(rate: 0.85, startTime: .hours(5)),
            BasalScheduleEntry(rate: 0.85, startTime: .hours(7.5)),
            BasalScheduleEntry(rate: 0.85, startTime: .hours(12.5)),
            BasalScheduleEntry(rate: 0.70, startTime: .hours(15)),
            BasalScheduleEntry(rate: 0.90, startTime: .hours(18)),
            BasalScheduleEntry(rate: 1.10, startTime: .hours(20)),
            ]
        
        let schedule = BasalSchedule(entries: entries)
        
        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp
        // PDM: 1a 1a 851072aa 00 0242 2a 1e50 0006 5008 3009 f808 3808 5007 3009 700b

        
        let hh       = 0x2a
        let ssss     = 0x1e50
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x851072aa, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a1a851072aa0002422a1e50000650083009f808380850073009700b", cmd1.data.hexadecimalString)
        
        //      13 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 2c 40 05 0262 00455b9c 01e0 015752a0 0168 01312d00 06a4 01432096 01a4 01885e6d 0168 01312d00 0370 00f9b074
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "132c4005026200455b9c01e0015752a0016801312d0006a40143209601a401885e6d016801312d00037000f9b074")!, cmd2.data)
    }
    
    func testRounding() {
        let entries = [
            BasalScheduleEntry(rate:  2.75, startTime: 0),
            BasalScheduleEntry(rate: 20.25, startTime: .hours(1)),
            BasalScheduleEntry(rate:  5.00, startTime: .hours(1.5)),
            BasalScheduleEntry(rate: 10.10, startTime: .hours(2)),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(2.5)),
            BasalScheduleEntry(rate:  3.50, startTime: .hours(15.5)),
            ]
        
        let schedule = BasalSchedule(entries: entries)
        
        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp
        // PDM: 1a 1e c2a32da8 00 053a 28 1af0 0010 181b 00ca 0032 0065 0001 f800 8800 f023 0023

        let hh       = 0x28
        let ssss     = 0x1af0
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0xc2a32da8, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a1ec2a32da800053a281af00010181b00ca003200650001f8008800f0230023", cmd1.data.hexadecimalString)
    }
    
    func testRounding2() {
        let entries = [
            BasalScheduleEntry(rate:  0.60, startTime: 0),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(7.5)),
            BasalScheduleEntry(rate:  0.50, startTime: .hours(8.5)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(9.5)),
            BasalScheduleEntry(rate:  0.15, startTime: .hours(15.5)),
            BasalScheduleEntry(rate:  0.80, startTime: .hours(16.3)),
            ]
        
        let schedule = BasalSchedule(entries: entries)
        
        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp
        // PDM: 1a 18 851072aa 00 021b 2c 2190 0004 f006 0007 1005 b806 1801 e008

        
        let hh       = 0x2c
        let ssss     = 0x2190
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x851072aa, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a18851072aa00021b2c21900004f00600071005b8061801e008", cmd1.data.hexadecimalString)
    }
    
    func testThirteenEntries() {
        let entries = [
            BasalScheduleEntry(rate:  1.30, startTime: 0),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(0.5)),
            BasalScheduleEntry(rate:  1.70, startTime: .hours(2.0)),
            BasalScheduleEntry(rate:  0.85, startTime: .hours(2.5)),
            BasalScheduleEntry(rate:  1.00, startTime: .hours(3.0)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(7.5)),
            BasalScheduleEntry(rate:  0.50, startTime: .hours(8.5)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(9.5)),
            BasalScheduleEntry(rate:  0.60, startTime: .hours(10.5)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(11.5)),
            BasalScheduleEntry(rate:  1.65, startTime: .hours(14.0)),
            BasalScheduleEntry(rate:  0.15, startTime: .hours(15.5)),
            BasalScheduleEntry(rate:  0.85, startTime: .hours(16.5)),
            ]
        
        let schedule = BasalSchedule(entries: entries)
        
        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp napp napp napp napp napp napp
        // PDM: 1a 2a 851072aa 00 01dd 27 1518 0003 000d 2800 0011 1809 700a 1806 1005 2806 1006 0007 2806 0011 1810 1801 e808
        
        
        let hh       = 0x27
        let ssss     = 0x1518
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd = SetInsulinScheduleCommand(nonce: 0x851072aa, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a2a851072aa0001dd2715180003000d280000111809700a180610052806100600072806001118101801e808", cmd.data.hexadecimalString)
        
        //      13 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 56 40 0c 02c8 011abc64 0082 00d34689 000f 15752a00 00aa 00a1904b 0055 01432096 0384 0112a880 0082 01a68d13 0064 02255100 0082 01a68d13 0078 01c9c380 0145 01a68d13 01ef 00a675a2 001e 07270e00 04fb 01432096
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "1356400c02c8011abc64008200d34689000f15752a0000aa00a1904b00550143209603840112a880008201a68d13006402255100008201a68d13007801c9c380014501a68d1301ef00a675a2001e07270e0004fb01432096")!, cmd2.data)

    }
    
    func testJoe12Entries() {
        let entries = [
            BasalScheduleEntry(rate:  1.30, startTime: 0),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(0.5)),
            BasalScheduleEntry(rate:  1.70, startTime: .hours(2.0)),
            BasalScheduleEntry(rate:  0.85, startTime: .hours(2.5)),
            BasalScheduleEntry(rate:  1.00, startTime: .hours(3.0)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(7.5)),
            BasalScheduleEntry(rate:  0.50, startTime: .hours(8.5)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(9.5)),
            BasalScheduleEntry(rate:  0.60, startTime: .hours(10.5)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(11.5)),
            BasalScheduleEntry(rate:  1.65, startTime: .hours(14.0)),
            BasalScheduleEntry(rate:  0.85, startTime: .hours(16)),
            ]
        
        let schedule = BasalSchedule(entries: entries)
        
        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp napp napp napp napp napp napp
        // PDM: 1a 2a f36a23a3 00 0291 03 0ae8 0000 000d 2800 0011 1809 700a 1806 1005 2806 1006 0007 2806 0011 2810 0009 e808
        
        
        let hh       = 0x03
        let ssss     = 0x0ae8
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0xf36a23a3, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a2af36a23a3000291030ae80000000d280000111809700a180610052806100600072806001128100009e808", cmd1.data.hexadecimalString)
    }
    
    func testBasalScheduleExtraCommandRoundsToNearestSecond() {
        let schedule = BasalSchedule(entries: [BasalScheduleEntry(rate: 1.0, startTime: 0)])
        
        let hh       = 0x2b
        let ssss     = 0x1b38
        
        //  Add 0.456 to the clock to have a non-integer # of seconds, and verify that it still produces valid results
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8)) + .seconds(0.456)
        
        // 13 LL RR MM NNNN XXXXXXXX YYYY ZZZZZZZZ
        // 13 0e 40 00 01c1 006acfc0 12c0 0112a880
        
        let cmd = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "130e400001c1006acfc012c00112a880")!, cmd.data)
    }

}
