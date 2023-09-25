//
//  PayloadSplitJoinTests.swift
//  OmniBLE
//
//  Created by Bill Gestrich on 12/11/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import OmniBLE

class PayloadSplitJoinTests: XCTestCase {

    func testSplitAndJoinBack() {
        for _ in 0...250 {
            let payload = Data(hexadecimalString: "54571003010003801781fc00fffffffe5350313d00041781fc012c5350323d000bffc32dbd08030e0100008a")!
            let splitter = PayloadSplitter(payload: payload)
            let packets = splitter.splitInPackets()
            let joiner = try! PayloadJoiner(firstPacket: packets[0].toData())
            for p in packets[1...] {
                try! joiner.accumulate(packet: p.toData())
            }
            let got = try! joiner.finalize()
            assert(got.hexadecimalString == payload.hexadecimalString)
        }
    }
}
