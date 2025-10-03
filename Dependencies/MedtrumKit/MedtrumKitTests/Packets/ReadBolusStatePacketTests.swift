@testable import MedtrumKit
import XCTest

final class ReadBolusStatePacketTests: XCTestCase {
    func testResponseGivenPacketWhenValuesSetThenReturnCorrectValues() throws {
        let response = Data([0, 34, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 47])
        var packet = ReadBolusStatePacket()

        packet.decode(response)
        XCTAssertFalse(packet.failed)

        _ = packet.parseResponse()
        // We dont test the response
    }

    func testResponseGivenResponseWhenMessageTooShortThenResultFalse() throws {
        let response = Data([0, 34, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])
        var packet = ReadBolusStatePacket()

        packet.decode(response)
        XCTAssertTrue(packet.failed)
    }
}
