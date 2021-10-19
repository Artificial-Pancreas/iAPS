//
//  MinimedPacketTests.swift
//  RileyLink
//
//  Created by Pete Schwamb on 2/27/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import XCTest
@testable import MinimedKit

class MinimedPacketTests: XCTestCase {
        
    func testDecode4b6b() {
        let input = Data(hexadecimalString: "ab2959595965574ab2d31c565748ea54e55a54b5558cd8cd55557194b56357156535ac5659956a55c55555556355555568bc5657255554e55a54b5555555b100")!
        let packet = MinimedPacket(encodedData: input)
        if let result = packet?.data {
            let expectedOutput = Data(hexadecimalString: "a259705504a24117043a0e080b003d3d00015b030105d817790a0f00000300008b1702000e080b0000")
            XCTAssertEqual(result, expectedOutput)
        } else {
            XCTFail("Unable to decode packet data")
        }
    }
    
    func testDecode4b6bWithBadData() {
        let packet = MinimedPacket(encodedData: Data(hexadecimalString: "0102030405")!)
        XCTAssertNil(packet)
    }
    
    func testInvalidCRC() {
        let inputWithoutCRC = Data(hexadecimalString: "a259705504a24117043a0e080b003d3d00015b030105d817790a0f00000300008b1702000e080b0000")!
        let packet = MinimedPacket(encodedData: Data(inputWithoutCRC.encode4b6b()))
        XCTAssertNil(packet)
    }

    func testEncode4b6b() {
        let input = Data(hexadecimalString: "a259705504a24117043a0e080b003d3d00015b030105d817790a0f00000300008b1702000e080b000071")!
        let packet = MinimedPacket(outgoingData: input)
        let expectedOutput = Data(hexadecimalString: "ab2959595965574ab2d31c565748ea54e55a54b5558cd8cd55557194b56357156535ac5659956a55c55555556355555568bc5657255554e55a54b5555555b1555000")
        XCTAssertEqual(packet.encodedData(), expectedOutput)
    }
}
