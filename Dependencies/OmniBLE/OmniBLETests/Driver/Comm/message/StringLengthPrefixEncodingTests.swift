//
//  StringLengthPrefixEncodingTests.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class StringLengthPrefixEncodingTests: XCTestCase {

    let p0Payload = Data(hexadecimalString: "50,30,3d,00,01,a5".replacingOccurrences(of: ",", with: ""))!
    let p0Content = Data(hexadecimalString:"a5")!

    func testFormatKeysP0() {
        let payload = StringLengthPrefixEncoding.formatKeys(keys: ["P0="], payloads: [p0Content])
        assert(p0Payload.hexadecimalString == payload.hexadecimalString)
    }

    func testParseKeysP0() {
        let parsed = try! StringLengthPrefixEncoding.parseKeys(["P0="], p0Payload)
        assert(parsed.count ==  1)
        assert(parsed[0].toHexString() == p0Content.toHexString())
    }
}
