//
//  ChangeMaxBasalRateMessageBodyTests.swift
//  MinimedKitTests
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ChangeMaxBasalRateMessageBodyTests: XCTestCase {

    func testMaxBasalRate() {
        var body = ChangeMaxBasalRateMessageBody(maxBasalUnitsPerHour: 6.4)!

        XCTAssertEqual(Data(hexadecimalString: "0201000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)

        body = ChangeMaxBasalRateMessageBody(maxBasalUnitsPerHour: 4.0)!

        XCTAssertEqual(Data(hexadecimalString: "0200A00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)
    }

    func testMaxBasalRateRounded() {
        let body = ChangeMaxBasalRateMessageBody(maxBasalUnitsPerHour: 9.115)!

        XCTAssertEqual(Data(hexadecimalString: "02016c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000")!, body.txData, body.txData.hexadecimalString)


    }

    func testMaxBasalRateOutOfRange() {
        XCTAssertNil(ChangeMaxBasalRateMessageBody(maxBasalUnitsPerHour: -1))
        XCTAssertNil(ChangeMaxBasalRateMessageBody(maxBasalUnitsPerHour: 36))
    }

}
