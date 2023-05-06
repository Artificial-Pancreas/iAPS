//
//  PacketTests.swift
//  OmniKitTests
//
//  Created by Pete Schwamb on 10/14/17.
//  Copyright © 2017 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import OmniKit

class PacketTests: XCTestCase {
    
    func testPacketData() {
        // 2016-06-26T20:33:28.412197 ID1:1f01482a PTYPE:PDM SEQ:13 ID2:1f01482a B9:10 BLEN:3 BODY:0e0100802c CRC:88
        
        let msg = Message(address: 0x1f01482a, messageBlocks: [GetStatusCommand()], sequenceNum: 4)
        
        let packet = Packet(address: 0x1f01482a, packetType: .pdm, sequenceNum: 13, data: msg.encoded())
        
        XCTAssertEqual("1f01482aad1f01482a10030e0100802c88", packet.encoded().hexadecimalString)
        
        XCTAssertEqual("1f01482a10030e0100802c", packet.data.hexadecimalString)

    }

    func testPacketDecoding() {
        do {
            let packet = try Packet(encodedData: Data(hexadecimalString:"1f01482aad1f01482a10030e0100802c88")!)
            XCTAssertEqual(0x1f01482a, packet.address)
            XCTAssertEqual(13, packet.sequenceNum)
            XCTAssertEqual(.pdm, packet.packetType)
            XCTAssertEqual("1f01482a10030e0100802c", packet.data.hexadecimalString)
        } catch (let error) {
            XCTFail("message decoding threw error: \(error)")
        }
    }

    func testPacketFragmenting() {
        let longMessageData = Data(hexadecimalString:"02cb5000c92162368024632d8029623f002c62320031623b003463320039633d003c63310041623e0044633200496340004c6333005163448101627c8104627c8109627c810c62198111627c811460198103fe")!
        let packet = Packet(address: 0x1f01482a, packetType: .pdm, sequenceNum: 13, data: longMessageData)
        XCTAssertEqual(31, packet.data.count)
        XCTAssertEqual("02cb5000c92162368024632d8029623f002c62320031623b00346332003963", packet.data.hexadecimalString)
        let con1 = Packet(address: 0x1f01482a, packetType: .con, sequenceNum: 14, data: longMessageData.subdata(in: 31..<longMessageData.count))
        XCTAssertEqual(31, con1.data.count)
        XCTAssertEqual("3d003c63310041623e0044633200496340004c6333005163448101627c8104", con1.data.hexadecimalString)
        let con2 = Packet(address: 0x1f01482a, packetType: .con, sequenceNum: 14, data: longMessageData.subdata(in: (31+31)..<longMessageData.count))
        XCTAssertEqual(21, con2.data.count)
        XCTAssertEqual("627c8109627c810c62198111627c811460198103fe", con2.data.hexadecimalString)
        XCTAssertEqual(longMessageData, packet.data + con1.data + con2.data)
    }
}

