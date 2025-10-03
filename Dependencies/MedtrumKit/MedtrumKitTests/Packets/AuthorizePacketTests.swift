@testable import MedtrumKit
import XCTest

final class AuthorizePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = AuthorizePacket(pumpSN: Data([217, 249, 118, 170]), sessionToken: Data([155, 2, 0, 0]))

        let expected = Data([14, 5, 0, 0, 2, 155, 2, 0, 0, 235, 57, 134, 200, 238, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([0, 5, 0, 0, 0, 0, 0, 80, 12, 1, 3, 103])
        var packet = AuthorizePacket(pumpSN: Data([217, 249, 118, 170]), sessionToken: Data([155, 2, 0, 0]))

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.deviceType, 80)
        XCTAssertEqual(actual.swVersion, "12.1.3")
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([0, 5, 0, 0, 0, 0, 0, 80, 12, 1, 3])
        var packet = AuthorizePacket(pumpSN: Data([217, 249, 118, 170]), sessionToken: Data([155, 2, 0, 0]))

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
