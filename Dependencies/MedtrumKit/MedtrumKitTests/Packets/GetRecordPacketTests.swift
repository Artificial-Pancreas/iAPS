@testable import MedtrumKit
import XCTest

final class GetRecordPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = GetRecordPacket(recordIndex: 4, patchId: Data([146, 0]))

        let expected = Data([9, 99, 0, 0, 4, 0, 146, 0, 246, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([
            35,
            99,
            9,
            1,
            0,
            0,
            170,
            28,
            2,
            255,
            251,
            216,
            229,
            238,
            14,
            0,
            192,
            1,
            165,
            236,
            174,
            17,
            165,
            236,
            174,
            17,
            1,
            0,
            26,
            0,
            0,
            0,
            154,
            0,
            208,
            4
        ])
        var packet = GetRecordPacket(recordIndex: 4, patchId: Data([146, 0]))

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        _ = packet.parseResponse()
        // We dont test the response
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([
            35,
            99,
            9,
            1,
            0,
            0,
            170,
            28,
            2,
            255,
            251,
            216,
            229,
            238,
            14,
            0,
            192,
            1,
            165,
            236,
            174,
            17,
            165,
            236,
            174,
            17,
            1,
            0,
            26,
            0,
            0,
            0,
            154,
            0,
            208
        ])
        var packet = GetRecordPacket(recordIndex: 4, patchId: Data([146, 0]))

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
