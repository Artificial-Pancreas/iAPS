@testable import MedtrumKit
import XCTest

final class GetTimePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = GetTimePacket()

        let expected = Data([5, 11, 0, 0, 161, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([0, 11, 0, 0, 0, 0, 224, 238, 88, 17, 22])
        var packet = GetTimePacket()

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.time, Date(timeIntervalSince1970: 1_679_575_392))
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([0, 11, 0, 0, 0, 0, 224, 238, 88, 17])
        var packet = GetTimePacket()

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
