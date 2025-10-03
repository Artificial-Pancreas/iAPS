@testable import MedtrumKit
import XCTest

final class CancelBolusPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = CancelBolusPacket()

        let expected = Data([6, 20, 0, 0, 1, 16, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
