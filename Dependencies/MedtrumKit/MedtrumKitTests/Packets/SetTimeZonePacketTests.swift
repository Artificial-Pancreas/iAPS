@testable import MedtrumKit
import XCTest

final class SetTimeZonePacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = SetTimeZonePacket(
            date: Date(timeIntervalSince1970: 1_741_721_000),
            timeZone: TimeZone.init(abbreviation: "CET")!
        )

        let expected = Data([11, 12, 0, 0, 60, 0, 40, 51, 13, 21, 110, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }

    func testRequestGMT12() throws {
        let input = SetTimeZonePacket(
            date: Date(timeIntervalSince1970: 1_741_721_000),
            timeZone: TimeZone.init(abbreviation: "UTC+13")!
        )

        // [108, 253] -> 64876
        let expected = Data([11, 12, 0, 0, 108, 253, 40, 51, 13, 21, 120, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
