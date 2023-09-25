//
//  ZeroBasalScheduleTests.swift
//  OmniBLE
//
//  Created by Joseph Moran on 03/19/2022.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class ZeroBasalScheduleTests: XCTestCase {

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

    func testZeroOneZeroSegment() {
        let entries = [
            BasalScheduleEntry(rate:  1.00, startTime: .hours(0)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(0.5)),
            BasalScheduleEntry(rate:  1.00, startTime: .hours(1.0)),
            ]
        
        let schedule = BasalSchedule(entries: entries)

        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp
        // PDM: 1a 16 494e532e 00 029b 13 1698 0004 000a 0000 f00a f00a d00a
        
        let hh       = 0x13
        let ssss     = 0x1698
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x494e532e, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a16494e532e00029b1316980004000a0000f00af00ad00a", cmd1.data.hexadecimalString)
        
        //      13 LL BO MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 1a 40 02 0b19 002dc6c0 0064 0112a880 0001 eb49d200 11f8 0112a880
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "131a40020b19002dc6c000640112a8800001eb49d20011f80112a880")!, cmd2.data)
    }

    func testZeroMinBasal() {
        let entries = [
            BasalScheduleEntry(rate:  0.00, startTime: .hours(0)),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(23)),
            ]
        
        let schedule = BasalSchedule(entries: entries)

        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp
        // PDM: 1a 14 494e532e 00 0097 28 3638 0000 f000 f000 e000 0001
        
        let hh       = 0x28
        let ssss     = 0x3638
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x494e532e, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a14494e532e0000972836380000f000f000e0000001", cmd1.data.hexadecimalString)
        
        //      13 LL BO MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 14 40 00 0006 6769ffc0 002e eb49d200 000a 15752a00
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "1314400000066769ffc0002eeb49d200000a15752a00")!, cmd2.data)
    }

    func testZeroSomeZeroBasal() {
        let entries = [
            BasalScheduleEntry(rate:  1.05, startTime: .hours(0)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(6)),
            BasalScheduleEntry(rate:  0.75, startTime: .hours(7.5)),
            BasalScheduleEntry(rate:  0.85, startTime: .hours(9)),
            BasalScheduleEntry(rate:  0.65, startTime: .hours(9.5)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(13.5)),
            BasalScheduleEntry(rate:  0.10, startTime: .hours(15.5)),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(17)),
            BasalScheduleEntry(rate:  0.20, startTime: .hours(19.5)),
            BasalScheduleEntry(rate:  0.35, startTime: .hours(21)),
            BasalScheduleEntry(rate:  2.75, startTime: .hours(22.5)),
            ]
        
        let schedule = BasalSchedule(entries: entries)

        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp napp napp napp
        // PDM: 1a 24 494e532e 00 018e 28 1518 0000 b80a 2000 2807 0009 7806 3000 2001 4800 2002 0004 1803 281b
        
        let hh       = 0x28
        let ssss     = 0x1518
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x494e532e, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a24494e532e00018e2815180000b80a2000280700097806300020014800200200041803281b", cmd1.data.hexadecimalString)
        
        //      13 LL BO MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 4a 40 08 001c 02aea540 04ec 01059449 0003 eb49d200 00e1 016e3600 0055 01432096 0208 01a68d13 0004 eb49d200 001e 0aba9500 0019 15752a00 003c 055d4a80 0069 0310bcdb 0339 0063e02e
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "134a4008001c02aea54004ec010594490003eb49d20000e1016e3600005501432096020801a68d130004eb49d200001e0aba9500001915752a00003c055d4a8000690310bcdb03390063e02e")!, cmd2.data)
    }

    func testZeroBasalTest1() {
        let entries = [
            BasalScheduleEntry(rate:  0.00, startTime: .hours(0)),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(1)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(2)),
            BasalScheduleEntry(rate:  0.15, startTime: .hours(3)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(5)),
            BasalScheduleEntry(rate:  0.20, startTime: .hours(7)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(9)),
            BasalScheduleEntry(rate:  0.25, startTime: .hours(11)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(14)),
            ]
        
        let schedule = BasalSchedule(entries: entries)

        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp napp
        // PDM: 1a 20 494e532e 00 0089 1b 1f30 0001 2000 0001 1000 3801 3000 3002 3000 5802 f000 3000
        
        let hh       = 0x1b
        let ssss     = 0x1f30
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x494e532e, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a20494e532e0000891b1f30000120000001100038013000300230005802f0003000", cmd1.data.hexadecimalString)
        
        //      13 LL BO MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 3e 40 07 000e 03b20b80 0002 eb49d200 000a 15752a00 0002 eb49d200 003c 07270e00 0004 eb49d200 0050 055d4a80 0004 eb49d200 0096 044aa200 0014 eb49d200
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "133e4007000e03b20b800002eb49d200000a15752a000002eb49d200003c07270e000004eb49d2000050055d4a800004eb49d2000096044aa2000014eb49d200")!, cmd2.data)
    }

    func testZeroBasalTest2() {
        let entries = [
            BasalScheduleEntry(rate:  0.00, startTime: .hours(0)),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(1)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(2)),
            BasalScheduleEntry(rate:  0.15, startTime: .hours(3)),
            BasalScheduleEntry(rate:  0.25, startTime: .hours(7)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(9)),
            BasalScheduleEntry(rate:  0.25, startTime: .hours(11)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(14)),
            BasalScheduleEntry(rate:  0.30, startTime: .hours(17)),
            ]
        
        let schedule = BasalSchedule(entries: entries)

        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp
        // PDM: 1a 1e 494e532e 00 00ca 1b 1e40 0001 2000 0001 1000 7801 3802 3000 5802 5000 d003

        let hh       = 0x1b
        let ssss     = 0x1e40
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x494e532e, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a1e494e532e0000ca1b1e40000120000001100078013802300058025000d003", cmd1.data.hexadecimalString)
        
        //      13 LL BO MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 3e 40 06 000e 01e84800 0002 eb49d200 000a 15752a00 0002 eb49d200 0078 07270e00 0064 044aa200 0004 eb49d200 0096 044aa200 0006 eb49d200 01a4 03938700
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "133e4006000e01e848000002eb49d200000a15752a000002eb49d200007807270e000064044aa2000004eb49d2000096044aa2000006eb49d20001a403938700")!, cmd2.data)
    }
    
    func testZeroBasalTest4() {
        let entries = [
            BasalScheduleEntry(rate:  0.00, startTime: .hours(0)),
            BasalScheduleEntry(rate:  0.05, startTime: .hours(1)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(2)),
            BasalScheduleEntry(rate:  0.15, startTime: .hours(3)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(5)),
            BasalScheduleEntry(rate:  0.20, startTime: .hours(7)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(9)),
            BasalScheduleEntry(rate:  0.25, startTime: .hours(11)),
            BasalScheduleEntry(rate:  0.00, startTime: .hours(12)),
            ]
        
        let schedule = BasalSchedule(entries: entries)

        //      1a LL NNNNNNNN 00 CCCC HH SSSS PPPP napp napp napp napp napp napp napp napp napp napp
        // PDM: 1a 20 494e532e 00 00bc 1b 1d70 0000 2000 0001 1000 3801 3000 3002 3000 1802 f000 7000
        
        let hh       = 0x1b
        let ssss     = 0x1d70
        let offset = TimeInterval(minutes: Double((hh + 1) * 30)) - TimeInterval(seconds: Double(ssss / 8))
        
        let cmd1 = SetInsulinScheduleCommand(nonce: 0x494e532e, basalSchedule: schedule, scheduleOffset: offset)
        XCTAssertEqual("1a20494e532e0000bc1b1d70000020000001100038013000300230001802f0007000", cmd1.data.hexadecimalString)
        
        //      13 LL BO MM NNNN XXXXXXXX YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ YYYY ZZZZZZZZ
        // PDM: 13 3e 40 08 0015 3825c780 0002 eb49d200 000a 15752a00 0002 eb49d200 003c 07270e00 0004 eb49d200 0050 055d4a80 0004 eb49d200 0032 044aa200 0018 eb49d200
        
        let cmd2 = BasalScheduleExtraCommand(schedule: schedule, scheduleOffset: offset, acknowledgementBeep: false, completionBeep: true, programReminderInterval: 0)
        checkBasalScheduleExtraCommandDataWithLessPrecision(Data(hexadecimalString: "133e400800153825c7800002eb49d200000a15752a000002eb49d200003c07270e000004eb49d2000050055d4a800004eb49d2000032044aa2000018eb49d200")!, cmd2.data)
    }

}
