@testable import MedtrumKit
import XCTest

final class StopPatchPacketTests: XCTestCase {
    func testRequestGivenPacketWhenValuesSetThenReturnCorrectByteArray() throws {
        let input = StopPatchPacket()

        let expected = Data([5, 31, 0, 0, 248, 0])

        let sequence: UInt8 = 0
        let actual = input.encode(sequenceNumber: sequence)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(actual[0], expected)
    }
}
