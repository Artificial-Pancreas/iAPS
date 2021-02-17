//
//  ReadOtherDevicesIDsMessageBodyTests.swift
//  MinimedKitTests
//
//  Copyright © 2018 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class ReadOtherDevicesIDsMessageBodyTests: XCTestCase {

    func test0IDs() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7594040f01f0015036800406001070636036f0040600107062f1dfc004020c107062f0e77000000000000000000000000000000000000000000000000000000000000000000")!)
        let body = message?.messageBody as! ReadOtherDevicesIDsMessageBody

        XCTAssertEqual(0, body.ids.count)
    }

    func test1IDs() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7594040f01f0101a21057280000000636036f0040600107062f1dfc004020c107062f0e77000000000000000000000000000000000000000000000000000000000000000000")!)
        let body = message?.messageBody as! ReadOtherDevicesIDsMessageBody

        XCTAssertEqual(1, body.ids.count)
        XCTAssertEqual("a2105728", body.ids[0].hexadecimalString)
    }

    func test2IDs() {
        let message = PumpMessage(rxData: Data(hexadecimalString: "a7594040f01f0201a210572800a2016016036f0040600107062f1dfc004020c107062f0e77000000000000000000000000000000000000000000000000000000000000000000")!)
        let body = message?.messageBody as! ReadOtherDevicesIDsMessageBody

        XCTAssertEqual(2, body.ids.count)
        XCTAssertEqual("a2105728", body.ids[0].hexadecimalString)
        XCTAssertEqual("a2016016", body.ids[1].hexadecimalString)
    }

}
