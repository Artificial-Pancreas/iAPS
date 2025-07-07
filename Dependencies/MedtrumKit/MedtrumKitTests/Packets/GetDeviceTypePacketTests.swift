@testable import MedtrumKit
import XCTest

final class GetDeviceTypePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = GetDeviceTypePacket()

        let expected = Data([5, 6, 0, 0, 65, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([0, 6, 0, 0, 0, 0, 80, 78, 97, 188, 0, 215])
        var packet = GetDeviceTypePacket()

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        let actual = packet.parseResponse()
        XCTAssertEqual(actual.deviceType, 80)
        XCTAssertEqual(actual.deviceSN, Data([78, 97, 188, 0]))
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([0, 6, 0, 0, 0, 0, 80, 78, 97, 188, 0])
        var packet = GetDeviceTypePacket()

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
